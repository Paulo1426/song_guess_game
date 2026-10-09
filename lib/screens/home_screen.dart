import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/nivel.dart';
import '../providers/providers.dart';
import '../services/firebase_game_repository.dart';
import '../services/offline_game_store.dart';
import 'game_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.authStateChanges});

  final Stream<User?>? authStateChanges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<User?>(
      stream: authStateChanges ?? FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('No se pudo consultar la sesión: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const FirebaseAuthScreen();
        return _AuthenticatedHome(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _AuthenticatedHome extends ConsumerStatefulWidget {
  const _AuthenticatedHome({super.key, required this.user});

  final User user;

  @override
  ConsumerState<_AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends ConsumerState<_AuthenticatedHome> {
  EstadoJuegoRemoto? _estado;
  Object? _error;
  bool _loading = true;
  bool _offlineMode = false;
  String? _startingLevelId;
  final _offlineStore = OfflineGameStore();
  OfflineGameSnapshot? _offlineSnapshot;

  @override
  void initState() {
    super.initState();
    if (widget.user.isAnonymous) {
      _iniciarSesionInvitado();
    } else {
      _cargar();
    }
  }

  Future<void> _iniciarSesionInvitado() async {
    try {
      await ref.read(firebaseGameRepositoryProvider).iniciarSesionInvitado();
      if (mounted) await _cargar();
    } catch (error) {
      if (!mounted) return;
      await _loadOfflineSnapshot(error);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      OfflineGameSnapshot? snapshot;
      try {
        snapshot = await _offlineStore.load(widget.user.uid);
      } on FormatException catch (error) {
        debugPrint('La copia offline está dañada: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La copia local de progreso no se pudo leer; se intentará recuperar desde internet.',
              ),
            ),
          );
        }
      } on FileSystemException catch (error) {
        debugPrint('No se pudo leer la copia offline: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo leer el almacenamiento local; se intentará cargar desde internet.',
              ),
            ),
          );
        }
      }
      if (snapshot != null) {
        await _syncPendingCompletions(snapshot);
      }
      final repository = ref.read(firebaseGameRepositoryProvider);
      final estado = await repository.cargarEstado();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _offlineMode = false;
        _loading = false;
      });
      try {
        final bundle = await repository.descargarPaqueteOffline();
        final refreshed = await _cacheOfflineBundle(
          bundle,
          widget.user.uid,
          widget.user.isAnonymous,
        );
        if (!mounted) return;
        setState(() => _offlineSnapshot = refreshed);
      } catch (error) {
        debugPrint('No se pudo actualizar el paquete offline: $error');
        if (snapshot == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudieron descargar todos los niveles para usarlos sin conexión.',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      await _loadOfflineSnapshot(error);
    }
  }

  Future<void> _loadOfflineSnapshot(Object onlineError) async {
    try {
      final snapshot = await _offlineStore.load(widget.user.uid);
      if (!mounted) return;
      if (snapshot == null) {
        setState(() {
          _error = onlineError;
          _loading = false;
        });
        return;
      }
      setState(() {
        _offlineSnapshot = snapshot;
        _estado = snapshot.estado;
        _offlineMode = true;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<OfflineGameSnapshot> _cacheOfflineBundle(
    Map<String, dynamic> bundle,
    String uid,
    bool guest,
  ) async {
    final state = Map<String, dynamic>.from(bundle['estado'] as Map);
    final rawLevels = bundle['levels'] as List<dynamic>;
    final audioService = ref.read(audioServiceProvider);
    final levels = await Future.wait(
      rawLevels.map((rawLevel) async {
        final data = Map<String, dynamic>.from(rawLevel as Map);
        final entry = Map<String, dynamic>.from(data['entry'] as Map);
        final nivelJson = Map<String, dynamic>.from(entry['nivel'] as Map);
        final nivel = Nivel.fromJson(nivelJson);
        final urls = Map<String, dynamic>.from(data['audioUrls'] as Map);
        final paths = <String, String>{};
        for (final instrument in nivel.instrumentos) {
          final url = urls[instrument.id];
          if (url is! String || url.isEmpty) {
            throw FormatException(
              'Falta el enlace offline del instrumento ${instrument.id} en ${nivel.id}',
            );
          }
          final key = 'level:${nivel.id}:stem:${instrument.id}';
          final file = await audioService.descargarYGuardar(url, key);
          paths[instrument.id] = file.path;
        }
        final instrumentalUrl = data['instrumentalAudioUrl'];
        if (instrumentalUrl is! String || instrumentalUrl.isEmpty) {
          throw FormatException(
            'Falta el enlace offline de la pista instrumental de ${nivel.id}',
          );
        }
        final instrumentalFile = await audioService.descargarYGuardar(
          instrumentalUrl,
          'song:${nivel.cancionId}:instrumentalSong',
        );
        return OfflineLevelData(
          nivel: nivel,
          completado: entry['completado'] as bool? ?? false,
          puedeIniciar: entry['puede_iniciar'] as bool? ?? false,
          respuesta: data['respuesta'] as String,
          audioPaths: paths,
          instrumentalAudioPath: instrumentalFile.path,
        );
      }),
    );
    final snapshot = OfflineGameSnapshot(
      uid: uid,
      guest: guest,
      stateJson: state,
      levels: levels,
      pendingCompletions: _offlineSnapshot?.uid == uid
          ? _offlineSnapshot!.pendingCompletions
          : const [],
    );
    await _offlineStore.save(snapshot);
    return snapshot;
  }

  Future<void> _syncPendingCompletions(OfflineGameSnapshot snapshot) async {
    var current = snapshot;
    final repository = ref.read(firebaseGameRepositoryProvider);
    for (final completion in snapshot.pendingCompletions) {
      final levelId = completion['levelId'];
      final answer = completion['answer'];
      if (levelId == null || answer == null) {
        throw const FormatException('Hay un progreso offline incompleto');
      }
      await repository.sincronizarNivelOffline(
        levelId: levelId,
        respuesta: answer,
      );
      current = current.withoutPendingCompletion(levelId);
      await _offlineStore.save(current);
    }
    _offlineSnapshot = current;
  }

  Future<bool> _iniciar(Nivel nivel, {int? numeroVisible}) async {
    if (_startingLevelId != null) return false;
    setState(() => _startingLevelId = nivel.id);
    try {
      OfflineLevelData? offlineLevel;
      for (final cachedLevel
          in _offlineSnapshot?.levels ?? const <OfflineLevelData>[]) {
        if (cachedLevel.nivel.id == nivel.id) {
          offlineLevel = cachedLevel;
          break;
        }
      }
      if (_offlineMode) {
        if (offlineLevel == null) {
          throw StateError('Este nivel no está descargado para jugar offline');
        }
        return await _pushGame(
          nivel: offlineLevel.nivel,
          gameId: 'offline-${DateTime.now().microsecondsSinceEpoch}',
          numeroVisible: numeroVisible,
          offlineLevel: offlineLevel,
        );
      }
      try {
        final partida = await ref
            .read(firebaseGameRepositoryProvider)
            .iniciarNivel(nivel.id);
        return await _pushGame(
          nivel: partida.nivel,
          gameId: partida.gameId,
          numeroVisible: numeroVisible,
          offlineLevel: offlineLevel,
        );
      } catch (error) {
        if (offlineLevel == null) rethrow;
        debugPrint(
          'No se pudo iniciar online; usando nivel descargado: $error',
        );
        return await _pushGame(
          nivel: offlineLevel.nivel,
          gameId: 'offline-${DateTime.now().microsecondsSinceEpoch}',
          numeroVisible: numeroVisible,
          offlineLevel: offlineLevel,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar el nivel: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _startingLevelId = null);
    }
  }

  Future<bool> _pushGame({
    required Nivel nivel,
    required String gameId,
    required int? numeroVisible,
    required OfflineLevelData? offlineLevel,
  }) async {
    if (!mounted) return false;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          nivel: nivel,
          gameId: gameId,
          numeroVisible: numeroVisible,
          offlineLevel: offlineLevel,
          offlineMode: _offlineMode || gameId.startsWith('offline-'),
          onOfflineCompleted: (levelId, answer) async {
            final snapshot = _offlineSnapshot;
            if (snapshot == null) {
              throw StateError('No existe progreso offline para sincronizar');
            }
            final updated = snapshot.completedLocally(levelId, answer);
            await _offlineStore.save(updated);
            _offlineSnapshot = updated;
          },
        ),
      ),
    );
    if (completed == true) await _cargar();
    return completed == true;
  }

  Future<void> _abrirDificultad(Dificultad dificultad) async {
    final estado = _estado;
    if (estado == null) return;
    final progreso = estado.dificultades.firstWhere(
      (item) => item.dificultad == dificultad,
    );
    final esDificultadActiva = estado.dificultadActiva == dificultad;
    final nivelesRemotos = esDificultadActiva
        ? estado.niveles
        : estado.nivelesRepetibles
              .where((item) => item.nivel.dificultad == dificultad)
              .toList(growable: false);
    final niveles = _offlineMode && _offlineSnapshot != null
        ? _offlineSnapshot!.levels
              .where((item) => item.nivel.dificultad == dificultad)
              .map(
                (item) => NivelAsignado(
                  nivel: item.nivel,
                  completado: item.completado,
                  puedeIniciar: item.puedeIniciar,
                ),
              )
              .toList(growable: false)
        : nivelesRemotos;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _DifficultyLevelsScreen(
          dificultad: dificultad,
          progreso: progreso,
          niveles: niveles,
          onStart: (nivel, numeroVisible) async {
            final completado = await _iniciar(
              nivel,
              numeroVisible: numeroVisible,
            );
            if (completado && mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    try {
      if (widget.user.isAnonymous) {
        await ref
            .read(firebaseGameRepositoryProvider)
            .finalizarSesionInvitado();
        await widget.user.delete();
      }
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar sesión: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adivina la canción'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorPanel(error: _error!, onRetry: _cargar)
          : estado == null
          ? const Center(child: Text('No se pudo cargar el progreso.'))
          : _ContenidoProgreso(
              estado: estado,
              esInvitado: widget.user.isAnonymous,
              offlineMode: _offlineMode,
              onOpenDifficulty: _abrirDificultad,
              onRefresh: _cargar,
            ),
    );
  }
}

class _ContenidoProgreso extends StatelessWidget {
  const _ContenidoProgreso({
    required this.estado,
    required this.esInvitado,
    required this.offlineMode,
    required this.onOpenDifficulty,
    required this.onRefresh,
  });

  final EstadoJuegoRemoto estado;
  final bool esInvitado;
  final bool offlineMode;
  final ValueChanged<Dificultad> onOpenDifficulty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cada dificultad tiene cinco niveles activos. Completa los cinco para desbloquear la siguiente.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (esInvitado) ...[
            const SizedBox(height: 8),
            const Text(
              'Modo invitado: el progreso se guarda en este dispositivo y se sincroniza '
              'cuando vuelvas a conectarte.',
            ),
          ],
          if (offlineMode) ...[
            const SizedBox(height: 8),
            const Text(
              'Sin conexión: estás jugando con los niveles descargados. '
              'El progreso se sincronizará cuando vuelvas a conectarte.',
            ),
          ],
          const SizedBox(height: 16),
          for (final progreso in estado.dificultades)
            Card(
              child: ListTile(
                leading: Icon(
                  progreso.desbloqueada ? Icons.lock_open : Icons.lock,
                ),
                title: Text(_nombreDificultad(progreso.dificultad)),
                onTap: progreso.desbloqueada
                    ? () => onOpenDifficulty(progreso.dificultad)
                    : null,
                subtitle: Text(
                  progreso.desbloqueada
                      ? progreso.total == 0
                            ? 'Publica 5 niveles para habilitar esta dificultad'
                            : '${progreso.completados}/${progreso.total} niveles completados'
                                  '${progreso.total < 5 ? ' · Se requieren 5 niveles publicados para avanzar' : ''}'
                      : 'Completa la dificultad anterior para desbloquearla',
                ),
                trailing: progreso.total > 0
                    ? SizedBox(
                        width: 72,
                        child: LinearProgressIndicator(
                          value: progreso.completados / progreso.total,
                        ),
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _DifficultyLevelsScreen extends StatelessWidget {
  const _DifficultyLevelsScreen({
    required this.dificultad,
    required this.progreso,
    required this.niveles,
    required this.onStart,
  });

  final Dificultad dificultad;
  final ProgresoDificultadRemoto progreso;
  final List<NivelAsignado> niveles;
  final Future<void> Function(Nivel nivel, int numeroVisible) onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_nombreDificultad(dificultad))),
      body: niveles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  progreso.total == 0
                      ? 'Todavía no hay niveles disponibles para esta dificultad.'
                      : 'No hay niveles completados para repetir.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: niveles.length,
              itemBuilder: (context, index) {
                final asignado = niveles[index];
                final canStart = asignado.completado || asignado.puedeIniciar;
                return Card(
                  child: ListTile(
                    title: Text('Nivel ${index + 1}'),
                    subtitle: Text(
                      asignado.completado
                          ? 'Completado'
                          : 'Canción por descubrir',
                    ),
                    trailing: asignado.completado
                        ? FilledButton.tonal(
                            onPressed: canStart
                                ? () => onStart(asignado.nivel, index + 1)
                                : null,
                            child: const Text('Repetir'),
                          )
                        : canStart
                        ? FilledButton(
                            onPressed: () => onStart(asignado.nivel, index + 1),
                            child: const Text('Jugar'),
                          )
                        : const Icon(Icons.lock_outline),
                  ),
                );
              },
            ),
    );
  }
}

String _nombreDificultad(Dificultad dificultad) {
  switch (dificultad) {
    case Dificultad.facil:
      return 'Fácil';
    case Dificultad.medio:
      return 'Media';
    case Dificultad.avanzado:
      return 'Avanzada';
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No se pudo cargar el progreso:\n$error'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class FirebaseAuthScreen extends StatefulWidget {
  const FirebaseAuthScreen({super.key});

  @override
  State<FirebaseAuthScreen> createState() => _FirebaseAuthScreenState();
}

class _FirebaseAuthScreenState extends State<FirebaseAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;
  Future<void>? _googleSignInReady;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_registering) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await credential.user?.updateDisplayName(_name.text.trim());
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (_googleSignInReady ??= GoogleSignIn.instance.initialize());
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google no devolvió un token de autenticación.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    } on GoogleSignInException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == GoogleSignInExceptionCode.canceled
              ? 'Se canceló el inicio de sesión con Google.'
              : error.description ?? error.code.name;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Adivina la canción',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_registering)
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Escribe tu nombre'
                          : null,
                    ),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (value) => value == null || !value.contains('@')
                        ? 'Escribe un correo válido'
                        : null,
                  ),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (value) => value == null || value.length < 6
                        ? 'Usa al menos 6 caracteres'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const CircularProgressIndicator()
                        : Text(
                            _registering ? 'Crear cuenta' : 'Iniciar sesión',
                          ),
                  ),
                  if (!_registering) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInWithGoogle,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continuar con Google'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _continueAsGuest,
                      child: const Text('Jugar sin registrarme'),
                    ),
                  ],
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _registering = !_registering;
                            _error = null;
                          }),
                    child: Text(
                      _registering ? 'Ya tengo cuenta' : 'Crear cuenta nueva',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
