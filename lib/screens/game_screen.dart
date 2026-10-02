import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nivel.dart';
import '../providers/providers.dart';

class GameScreen extends ConsumerStatefulWidget {
  final Nivel nivel;
  final String gameId;

  const GameScreen({super.key, required this.nivel, required this.gameId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _answerController = TextEditingController();
  bool _sending = false;
  String? _message;
  bool? _correct;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
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
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¡Correcto!'),
            content: const Text(
              'Nivel completado. Tu progreso quedó guardado.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
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
    appBar: AppBar(title: Text('Nivel ${widget.nivel.numero}')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Envía tu respuesta para validarla. El servidor no revela la canción hasta completar el nivel.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final instrumento in widget.nivel.instrumentos)
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(instrumento.nombre),
            subtitle: Text('\$${instrumento.precio}'),
          ),
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
        FilledButton(
          onPressed: _sending ? null : _submitAnswer,
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
