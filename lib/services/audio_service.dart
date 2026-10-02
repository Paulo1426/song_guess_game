import 'package:just_audio/just_audio.dart';

class AudioService {
  final List<AudioPlayer> _players = [];
  bool _reproduciendo = false;

  bool get reproduciendo => _reproduciendo;

  Future<void> reproducir({
    required List<String> urls,
    Duration inicio = Duration.zero,
    Duration duracion = const Duration(seconds: 5),
  }) async {
    if (urls.isEmpty) {
      throw ArgumentError('No hay audios para reproducir');
    }
    await detener();
    for (final url in urls) {
      final player = AudioPlayer();
      await player.setUrl(url);
      await player.seek(inicio);
      _players.add(player);
    }
    _reproduciendo = true;
    try {
      await Future.wait(_players.map((player) => player.play()));
      await Future.delayed(duracion);
    } finally {
      await detener();
    }
  }

  Future<void> detener() async {
    _reproduciendo = false;
    final players = List<AudioPlayer>.from(_players);
    _players.clear();
    for (final player in players) {
      await player.stop();
      await player.dispose();
    }
  }
}