import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/instrumento.dart';
import '../models/nivel.dart';
import '../providers/providers.dart';
import '../services/audio_service.dart';

class GameScreen extends ConsumerStatefulWidget {
  final Nivel nivel;
  final String gameId;
  final int? numeroVisible;

  const GameScreen({
    super.key,
    required this.nivel,
    required this.gameId,
    this.numeroVisible,
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _answerController = TextEditingController();
  late final AudioService _audioService;
  bool _sending = false;
  bool _buying = false;
  bool _playing = false;
  String? _message;
  bool? _correct;
  int _balance = Nivel.presupuestoTotal;
  final Set<String> _purchased = {};
  bool _melodyFound = false;
  bool _won = false;
  int _playbackGeneration = 0;

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
  }

  @override
  void dispose() {
    _playbackGeneration++;
    _answerController.dispose();
    unawaited(_stopAudioOnDispose());
    super.dispose();
  }

  Future<void> _stopAudioOnDispose() async {
    try {
      await _audioService.detener();
    } catch (error, stackTrace) {
      debugPrint('No se pudo detener el audio al salir del nivel: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _buyAndPlay(Instrumento instrumento) async {
    if (_buying || _playing || _won) return;
    if (_melodyFound || _purchased.contains(instrumento.id)) {
      try {
        await _playStems([instrumento]);
      } catch (error) {
        if (mounted) {
          setState(
            () => _message = 'No se pudo reproducir el instrumento: $error',
          );
        }
      }
      return;
    }

    setState(() {
      _buying = true;
      _message = null;
    });
    try {
      final repository = ref.read(firebaseGameRepositoryProvider);
      final result = await repository.comprarInstrumento(
        gameId: widget.gameId,
        instrumento: instrumento.id,
      );
      if (!mounted) return;
      final purchasePrice =
          'Instrumento comprado por \$${_formatPriceInThousands(result.precioInstrumento)}K.';
      setState(() {
        _balance = result.presupuestoRestante;
        _purchased
          ..clear()
          ..addAll(result.instrumentosComprados);
        _melodyFound = result.melodiaDescubierta;
        _message = result.melodiaDescubierta
            ? '¡Encontraste la melodía! Se desbloquearon todos los instrumentos. '
                  '$purchasePrice'
            : result.compraRealizada
            ? purchasePrice
            : null;
      });
      try {
        await _playStems([instrumento]);
      } catch (error) {
        if (!mounted) return;
        setState(
          () => _message =
              '$purchasePrice No se pudo reproducir el instrumento: $error',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No se pudo comprar el instrumento: $error');
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _playPurchased() async {
    if (_playing || _buying) return;
    final instruments = _melodyFound
        ? widget.nivel.instrumentos
        : widget.nivel.instrumentos
              .where((instrument) => _purchased.contains(instrument.id))
              .toList(growable: false);
    if (instruments.isEmpty) return;
    try {
      await _playStems(instruments);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No se pudieron reproducir los instrumentos: $error',
        );
      }
    }
  }

  Future<void> _playStems(List<Instrumento> instruments) async {
    final playbackGeneration = ++_playbackGeneration;
    setState(() => _playing = true);
    try {
      final repository = ref.read(firebaseGameRepositoryProvider);
      final audio = await Future.wait(
        instruments.map((instrument) async {
          final cacheKey =
              'stem:${widget.gameId}:${instrument.id}:${widget.nivel.puntosInicio.join(",")}';
          final cachedFile = await _audioService.cachedFile(cacheKey);
          if (cachedFile != null) {
            return (Uri.file(cachedFile.path).toString(), null);
          }
          final url = await repository.obtenerUrlAudio(
            gameId: widget.gameId,
            tipo: 'stem',
            instrumento: instrument.id,
          );
          return (url, cacheKey);
        }),
      );
      if (!mounted) return;
      await _audioService.reproducir(
        urls: audio.map((item) => item.$1).toList(growable: false),
        cacheKeys: audio.map((item) => item.$2).toList(growable: false),
        duracion: Duration(seconds: widget.nivel.duracionFragmentoSegundos),
      );
    } finally {
      if (mounted && playbackGeneration == _playbackGeneration) {
        setState(() => _playing = false);
      }
    }
  }

  Future<void> _playSong(String type, {bool replaceCurrent = false}) async {
    if (_playing && !replaceCurrent) return;
    final playbackGeneration = ++_playbackGeneration;
    setState(() => _playing = true);
    try {
      final cacheKey = 'song:${widget.nivel.cancionId}:$type';
      final cachedFile = await _audioService.cachedFile(cacheKey);
      final url = cachedFile == null
          ? await ref
                .read(firebaseGameRepositoryProvider)
                .obtenerUrlAudio(gameId: widget.gameId, tipo: type)
          : Uri.file(cachedFile.path).toString();
      if (!mounted) return;
      await _audioService.reproducir(
        urls: [url],
        cacheKeys: [cachedFile == null ? cacheKey : null],
        duracion: null,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No se pudo reproducir la canción: $error');
      }
    } finally {
      if (mounted && playbackGeneration == _playbackGeneration) {
        setState(() => _playing = false);
      }
    }
  }

  Future<void> _submitAnswer() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _message = null;
      _correct = null;
    });
    try {
      final correct = await ref
          .read(firebaseGameRepositoryProvider)
          .enviarRespuesta(gameId: widget.gameId, respuesta: answer);
      if (!mounted) return;
      if (correct) {
        _playbackGeneration++;
        setState(() {
          _won = true;
          _correct = true;
          _message = '¡Correcto! Reproduciendo la canción original.';
        });
        try {
          await _audioService.detener();
        } catch (error) {
          if (mounted) {
            setState(() {
              _playing = false;
              _message =
                  'Respuesta correcta, pero no se pudo detener el audio anterior: $error';
            });
          }
          return;
        }
        if (!mounted) return;
        await _playSong('fullSong', replaceCurrent: true);
      } else {
        setState(() {
          _correct = false;
          _message = 'Esa no es la canción. Intenta de nuevo.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'No se pudo validar la respuesta: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Nivel ${widget.numeroVisible ?? widget.nivel.numero}'),
      actions: [
        if (_playing)
          IconButton(
            tooltip: 'Detener audio',
            onPressed: () => _audioService.detener(),
            icon: const Icon(Icons.stop),
          ),
        if (_won)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terminar'),
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.nivel.modoPrueba
              ? 'Modo de prueba: ${widget.nivel.duracionFragmentoSegundos} segundos por escucha.'
              : 'Compra un instrumento para escuchar un fragmento de la canción.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text('Presupuesto restante: \$$_balance'),
        const SizedBox(height: 4),
        Text(
          'Puedes comprar hasta 3 de los ${widget.nivel.instrumentos.length} instrumentos.',
        ),
        const SizedBox(height: 8),
        for (final instrumento in widget.nivel.instrumentos)
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(instrumento.nombre),
            trailing: IconButton(
              onPressed:
                  _buying ||
                      _playing ||
                      _won ||
                      (!_melodyFound &&
                          !_purchased.contains(instrumento.id) &&
                          _purchased.length >= 3)
                  ? null
                  : () => _buyAndPlay(instrumento),
              tooltip:
                  !_melodyFound &&
                      !_purchased.contains(instrumento.id) &&
                      _purchased.length >= 3
                  ? 'Ya compraste el máximo de 3 instrumentos'
                  : _purchased.contains(instrumento.id) || _melodyFound
                  ? 'Escuchar ${instrumento.nombre}'
                  : 'Comprar y escuchar ${instrumento.nombre}',
              icon: Icon(
                _purchased.contains(instrumento.id) || _melodyFound
                    ? Icons.play_arrow
                    : Icons.shopping_cart,
              ),
            ),
          ),
        if (_purchased.isNotEmpty || _melodyFound) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _buying || _playing ? null : _playPurchased,
            icon: const Icon(Icons.queue_music),
            label: Text(
              _melodyFound
                  ? 'Escuchar todos los instrumentos'
                  : 'Escuchar instrumentos comprados',
            ),
          ),
        ],
        const Divider(height: 32),
        TextField(
          controller: _answerController,
          enabled: !_sending,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitAnswer(),
          decoration: const InputDecoration(
            labelText: '¿Qué canción es?',
            border: OutlineInputBorder(),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: TextStyle(
              color: _correct == false
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_melodyFound)
          FilledButton.icon(
            onPressed: _playing ? null : () => _playSong('instrumentalSong'),
            icon: const Icon(Icons.queue_music),
            label: const Text('Escuchar canción sin voz'),
          ),
        if (_won) ...[
          FilledButton.icon(
            onPressed: _playing ? null : () => _playSong('fullSong'),
            icon: const Icon(Icons.library_music),
            label: const Text('Escuchar canción original'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Terminar nivel'),
          ),
        ],
        FilledButton(
          onPressed: _sending || _won ? null : _submitAnswer,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Comprobar respuesta'),
        ),
      ],
    ),
  );
}

String _formatPriceInThousands(int price) => (price ~/ 1000).toString();
