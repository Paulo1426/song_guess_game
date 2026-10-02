import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nivel.dart';

class GameScreen extends ConsumerStatefulWidget {
  final Nivel nivel;
  const GameScreen({super.key, required this.nivel});
  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Nivel ${widget.nivel.numero}')),
        body: ListView.builder(
          itemCount: widget.nivel.instrumentos.length,
          itemBuilder: (context, index) {
            final instrumento = widget.nivel.instrumentos[index];
            return ListTile(
              title: Text(instrumento.nombre),
              subtitle: Text('\$${instrumento.precio}'),
            );
          },
        ),
      );
}