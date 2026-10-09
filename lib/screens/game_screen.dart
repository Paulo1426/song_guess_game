import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/instrumento.dart';
import '../models/nivel.dart';
import '../models/partida.dart';
import '../providers/providers.dart';
import '../services/audio_service.dart';
import '../services/firebase_game_repository.dart';
import '../services/offline_game_store.dart';

class GameScreen extends ConsumerStatefulWidget {
  final Nivel nivel;
  final String gameId;
  final int? numeroVisible;
  final bool offlineMode;
  final OfflineLevelData? offlineLevel;
  final Future<void> Function(String levelId, String answer)?
  onOfflineCompleted;

  const GameScreen({
    super.key,
    required this.nivel,
    required this.gameId,
    this.numeroVisible,
    this.offlineMode = false,
    this.offlineLevel,
    this.onOfflineCompleted,
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
  late bool _playingOffline;
  int _playbackGeneration = 0;
  late final Partida? _offlinePartida;

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    _playingOffline = widget.offlineMode;
    _offlinePartida = widget.offlineLevel != null
        ? Partida(
            instrumentos: widget.nivel.instrumentos,
            random: Random.secure(),
          )
        : null;
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
    if (_playingOffline) {
      await _buyOfflineInstrument(instrumento);
      return;
    }
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
      if (widget.offlineLevel != null && mounted) {
        debugPrint('No se pudo comprar online; continuará offline: $error');
        setState(() => _playingOffline = true);
        await _buyOfflineInstrument(instrumento);
        return;
      }
      if (mounted) {
        setState(() => _message = 'No se pudo comprar el instrumento: $error');
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _buyOfflineInstrument(Instrumento instrumento) async {
    try {
      final partida = _offlinePartida!;
      if (!partida.comprarTipo(instrumento.tipo)) {
        throw StateError('No se pudo comprar el instrumento offline');
      }
      final price = partida.precioDe(instrumento.tipo)!;
      var melodyFound = false;
      if (partida.comprados.length == Partida.maxInstrumentosComprados) {
        final random = Random.secure();
        final unpurchased = widget.nivel.instrumentos
            .where((item) => !partida.comprados.contains(item.tipo))
            .toList(growable: false);
        final melody = unpurchased.isNotEmpty && random.nextInt(10) < 7
            ? unpurchased.first.tipo
            : partida.comprados[random.nextInt(partida.comprados.length)];
        partida.descubrirMelodia(melody);
        melodyFound = partida.melodiaDescubierta;
      }
      if (!mounted) return;
      final purchasePrice =
          'Instrumento comprado por \$${_formatPriceInThousands(price)}K.';
      setState(() {
        _balance = partida.presupuestoRestante;
        _purchased
          ..clear()
          ..addAll(partida.comprados.map((item) => item.id));
        _melodyFound = melodyFound;
        _message = melodyFound
            ? '¡Encontraste la melodía! Se desbloquearon todos los instrumentos. '
                  '$purchasePrice'
            : purchasePrice;
      });
      await _playStems([instrumento]);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No se pudo comprar el instrumento offline: $error',
        );
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
          final cacheKey = 'level:${widget.nivel.id}:stem:${instrument.id}';
          final offlinePath = widget.offlineLevel?.audioPaths[instrument.id];
          if (offlinePath != null && await File(offlinePath).exists()) {
            return (Uri.file(offlinePath).toString(), null);
          }
          if (_playingOffline) {
            throw StateError(
              'El audio ${instrument.nombre} no está descargado en este dispositivo',
            );
          }
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
    if (_playingOffline && type == 'fullSong') {
      setState(
        () => _message =
            'La canción completa se reproducirá cuando tengas conexión a internet.',
      );
      return;
    }
    final playbackGeneration = ++_playbackGeneration;
    setState(() => _playing = true);
    try {
      String url;
      String? cacheKey;
      if (type == 'instrumentalSong') {
        final offlinePath = widget.offlineLevel?.instrumentalAudioPath;
        if (offlinePath != null && await File(offlinePath).exists()) {
          url = Uri.file(offlinePath).toString();
        } else {
          final instrumentalCacheKey =
              'song:${widget.nivel.cancionId}:instrumentalSong';
          final cachedFile = await _audioService.cachedFile(
            instrumentalCacheKey,
          );
          if (cachedFile != null) {
            url = Uri.file(cachedFile.path).toString();
          } else if (_playingOffline) {
            throw StateError(
              'La pista instrumental no está descargada en este dispositivo',
            );
          } else {
            url = await ref
                .read(firebaseGameRepositoryProvider)
                .obtenerUrlAudio(gameId: widget.gameId, tipo: type);
            cacheKey = instrumentalCacheKey;
          }
        }
      } else {
        url = await ref
            .read(firebaseGameRepositoryProvider)
            .obtenerUrlAudio(gameId: widget.gameId, tipo: type);
      }
      if (!mounted) return;
      await _audioService.reproducir(
        urls: [url],
        cacheKeys: [cacheKey],
        duracion: null,
      );
    } catch (error) {
      if (mounted) {
        if (widget.offlineLevel != null && type == 'fullSong') {
          setState(() {
            _playingOffline = true;
            _message =
                'La canción completa se reproducirá cuando tengas conexión a internet.';
          });
          return;
        }
        setState(
          () => _message = type == 'instrumentalSong'
              ? 'No se pudo reproducir la pista instrumental: $error'
              : 'No se pudo reproducir la canción: $error',
        );
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
      if (_playingOffline) {
        await _checkOfflineAnswer(answer);
        return;
      }
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
        if (widget.offlineLevel != null &&
            !_playingOffline &&
            error is! GameRepositoryException) {
          debugPrint('No se pudo validar online; comprobando offline: $error');
          setState(() => _playingOffline = true);
          try {
            await _checkOfflineAnswer(answer);
          } catch (offlineError) {
            if (mounted) {
              setState(
                () => _message =
                    'No se pudo guardar el progreso offline: $offlineError',
              );
            }
          }
        } else {
          setState(() {
            if (error is GameRepositoryException && error.statusCode == 429) {
              _message = error.message;
            } else {
              _message = _playingOffline
                  ? 'No se pudo guardar el progreso offline: $error'
                  : 'No se pudo validar la respuesta: $error';
            }
          });
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkOfflineAnswer(String answer) async {
    final offlineLevel = widget.offlineLevel;
    if (offlineLevel == null) {
      throw StateError('El nivel no está guardado para jugar offline');
    }
    final correct =
        OfflineGameStore.normalizeAnswer(answer) ==
        OfflineGameStore.normalizeAnswer(offlineLevel.respuesta);
    if (!mounted) return;
    if (!correct) {
      setState(() {
        _correct = false;
        _message = 'Esa no es la canción. Intenta de nuevo.';
      });
      return;
    }
    await widget.onOfflineCompleted?.call(widget.nivel.id, answer);
    if (!mounted) return;
    _playbackGeneration++;
    setState(() {
      _won = true;
      _correct = true;
      _message =
          '¡Correcto! La canción completa se reproducirá cuando tengas conexión a internet.';
    });
    await _audioService.detener();
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
            onPressed: _playing || _playingOffline
                ? null
                : () => _playSong('fullSong'),
            icon: const Icon(Icons.library_music),
            label: Text(
              _playingOffline
                  ? 'Canción original disponible con internet'
                  : 'Escuchar canción original',
            ),
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
