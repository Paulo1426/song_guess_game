import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  final http.Client _httpClient = http.Client();
  final List<AudioPlayer> _players = [];
  bool _reproduciendo = false;
  Completer<void>? _cancelPlayback;
  int _playbackGeneration = 0;

  bool get reproduciendo => _reproduciendo;

  Future<File?> cachedFile(String key) async {
    final file = await _cacheFile(key);
    return await file.exists() ? file : null;
  }

  Future<void> reproducir({
    required List<String> urls,
    List<String?>? cacheKeys,
    Duration inicio = Duration.zero,
    Duration? duracion = const Duration(seconds: 5),
  }) async {
    if (urls.isEmpty) {
      throw ArgumentError('No hay audios para reproducir');
    }
    if (cacheKeys != null && cacheKeys.length != urls.length) {
      throw ArgumentError('Debe existir una clave de caché por cada audio');
    }
    final playbackGeneration = ++_playbackGeneration;
    await _detenerPlayers();
    if (playbackGeneration != _playbackGeneration) return;
    final cancellation = Completer<void>();
    _cancelPlayback = cancellation;
    try {
      for (final url in urls) {
        if (!identical(_cancelPlayback, cancellation)) return;
        final player = AudioPlayer();
        _players.add(player);
        final index = _players.length - 1;
        final cacheKey = cacheKeys == null ? null : cacheKeys[index];
        if (cacheKey == null) {
          final uri = Uri.parse(url);
          if (uri.scheme == 'file') {
            await player.setFilePath(uri.toFilePath());
          } else {
            await player.setUrl(url);
          }
        } else {
          final file = await _ensureCached(url, cacheKey);
          await player.setFilePath(file.path);
        }
        if (!identical(_cancelPlayback, cancellation)) return;
        await player.seek(inicio);
      }
      if (!identical(_cancelPlayback, cancellation)) return;
      _reproduciendo = true;
      final playback = Future.wait(
        _players.map((player) => player.play()),
      ).then<void>((_) {});
      final events = <Future<void>>[playback, cancellation.future];
      if (duracion != null) events.add(Future<void>.delayed(duracion));
      await Future.any<void>(events);
    } catch (error) {
      if (identical(_cancelPlayback, cancellation)) rethrow;
    } finally {
      if (identical(_cancelPlayback, cancellation)) {
        await detener();
      }
    }
  }

  Future<void> detener() async {
    _playbackGeneration++;
    await _detenerPlayers();
  }

  Future<File> _cacheFile(String key) async {
    final directory = await getApplicationSupportDirectory();
    final cacheDirectory = Directory('${directory.path}/audio_cache');
    await cacheDirectory.create(recursive: true);
    final fileName = sha256.convert(utf8.encode(key)).toString();
    return File('${cacheDirectory.path}/$fileName.mp3');
  }

  Future<File> _ensureCached(String url, String key) async {
    final file = await _cacheFile(key);
    if (await file.exists() && await file.length() > 0) return file;

    final partialFile = File('${file.path}.download');
    if (await partialFile.exists()) await partialFile.delete();
    final response = await _httpClient.send(
      http.Request('GET', Uri.parse(url)),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'No se pudo descargar el audio (${response.statusCode})',
        uri: Uri.parse(url),
      );
    }
    try {
      await response.stream.pipe(partialFile.openWrite());
      if (!await partialFile.exists() || await partialFile.length() == 0) {
        throw const FileSystemException('El audio descargado está vacío');
      }
      return await partialFile.rename(file.path);
    } catch (_) {
      if (await partialFile.exists()) await partialFile.delete();
      rethrow;
    }
  }

  Future<void> _detenerPlayers() async {
    _reproduciendo = false;
    final cancellation = _cancelPlayback;
    _cancelPlayback = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    final players = List<AudioPlayer>.from(_players);
    _players.clear();
    await Future.wait(
      players.map((player) async {
        try {
          await player.stop();
        } finally {
          await player.dispose();
        }
      }),
    );
  }
}
