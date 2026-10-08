import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/nivel.dart';
import '../providers/providers.dart';
import '../services/firebase_game_repository.dart';
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
  String? _startingLevelId;

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
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final estado = await ref
          .read(firebaseGameRepositoryProvider)
          .cargarEstado();
      if (!mounted) return;
      setState(() {
        _estado = estado;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _iniciar(Nivel nivel) async {
    setState(() => _startingLevelId = nivel.id);
    try {
      final repository = ref.read(firebaseGameRepositoryProvider);
      final partida = await repository.iniciarNivel(nivel.id);
      if (!mounted) return;
      final completada = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              GameScreen(nivel: partida.nivel, gameId: partida.gameId),
        ),
      );
      if (completada == true) await _cargar();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar el nivel: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingLevelId = null);
    }
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
              startingLevelId: _startingLevelId,
              onStart: _iniciar,
              onRefresh: _cargar,
            ),
    );
  }
}

class _ContenidoProgreso extends StatelessWidget {
  const _ContenidoProgreso({
    required this.estado,
    required this.esInvitado,
    required this.startingLevelId,
    required this.onStart,
    required this.onRefresh,
  });

  final EstadoJuegoRemoto estado;
  final bool esInvitado;
  final String? startingLevelId;
  final ValueChanged<Nivel> onStart;
  final Future<void> Function() onRefresh;
  bool get _starting => startingLevelId != null;

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
              'Modo invitado: puedes avanzar y completar niveles durante esta sesión. '
              'El progreso se reinicia cuando cierres y vuelvas a abrir la app.',
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
          Text(
            'Orden personal: ${_nombreDificultad(estado.dificultadActiva)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (estado.niveles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Todavía no hay niveles publicados para esta dificultad. '
                'Se requieren cinco niveles publicados para completarla.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final asignado in estado.niveles)
            Card(
              child: ListTile(
                title: Text('Nivel ${asignado.nivel.numero}'),
                subtitle: Text(
                  asignado.completado ? 'Completado' : 'Canción por descubrir',
                ),
                trailing: asignado.completado
                    ? FilledButton.tonal(
                        onPressed: _starting
                            ? null
                            : () => onStart(asignado.nivel),
                        child: startingLevelId == asignado.nivel.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Repetir'),
                      )
                    : asignado.puedeIniciar
                    ? FilledButton(
                        onPressed: startingLevelId == null
                            ? () => onStart(asignado.nivel)
                            : null,
                        child: startingLevelId == asignado.nivel.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Jugar'),
                      )
                    : const Icon(Icons.lock_outline),
              ),
            ),
          if (estado.niveles.isNotEmpty &&
              estado.niveles.every((nivel) => nivel.completado))
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                estado.dificultades
                            .firstWhere(
                              (progreso) =>
                                  progreso.dificultad ==
                                  estado.dificultadActiva,
                            )
                            .total <
                        5
                    ? 'Completaste los niveles publicados. Se necesitan 5 niveles publicados para completar esta dificultad.'
                    : estado.dificultadActiva == Dificultad.avanzado
                    ? '¡Completaste los cinco niveles de esta dificultad!'
                    : '¡Completaste los cinco niveles! Se desbloqueará la siguiente dificultad.',
                textAlign: TextAlign.center,
              ),
            ),
          if (estado.nivelesRepetibles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Repetir niveles completados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final asignado in estado.nivelesRepetibles)
              Card(
                child: ListTile(
                  title: Text(
                    'Nivel ${asignado.nivel.numero} · ${_nombreDificultad(asignado.nivel.dificultad)}',
                  ),
                  subtitle: const Text('Completado'),
                  trailing: FilledButton.tonal(
                    onPressed: _starting ? null : () => onStart(asignado.nivel),
                    child: startingLevelId == asignado.nivel.id
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Repetir'),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _nombreDificultad(Dificultad dificultad) {
    switch (dificultad) {
      case Dificultad.facil:
        return 'Fácil';
      case Dificultad.medio:
        return 'Media';
      case Dificultad.avanzado:
        return 'Avanzada';
    }
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
