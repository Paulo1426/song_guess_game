import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/instrumento.dart';
import '../models/nivel.dart';

class SupabaseNivelRepository {
  final SupabaseClient _client;

  SupabaseNivelRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<Nivel>> nivelesDe(Dificultad dificultad) async {
    final rows = await _client
        .from('niveles')
        .select('''
          id, numero, dificultad, cancion_id, instrumento_melodia,
          puntos_inicio, canciones!inner(id, titulo),
          nivel_instrumentos!inner(tipo, precio, audio_path)
        ''')
        .eq('dificultad', dificultad.id)
        .order('numero');

    return rows.map((row) => _nivelDesdeRow(row)).toList();
  }

  Future<Nivel> obtener(String nivelId) async {
    final row = await _client.from('niveles').select('''
      id, numero, dificultad, cancion_id, instrumento_melodia,
      puntos_inicio, canciones!inner(id, titulo),
      nivel_instrumentos!inner(tipo, precio, audio_path)
    ''').eq('id', nivelId).single();
    return _nivelDesdeRow(row);
  }

  Nivel _nivelDesdeRow(Map<String, dynamic> row) {
    final cancion = row['canciones'] as Map<String, dynamic>;
    final instrumentos = (row['nivel_instrumentos'] as List<dynamic>)
        .map((item) {
          final value = item as Map<String, dynamic>;
          return Instrumento(
            tipo: TipoInstrumentoExtension.fromId(value['tipo'] as String),
            precio: (value['precio'] as num).toInt(),
            audioUrl: _client.storage
                .from('instrumentos')
                .getPublicUrl(value['audio_path'] as String),
          );
        })
        .toList();

    return Nivel(
      id: row['id'] as String,
      numero: (row['numero'] as num).toInt(),
      dificultad: DificultadExtension.fromId(row['dificultad'] as String),
      cancionId: cancion['id'] as String,
      cancionTitulo: cancion['titulo'] as String,
      instrumentos: instrumentos,
      instrumentoMelodia: TipoInstrumentoExtension.fromId(
        row['instrumento_melodia'] as String,
      ),
      puntosInicio: ((row['puntos_inicio'] as List<dynamic>?) ?? [])
          .map((value) => (value as num).toInt())
          .toList(),
    );
  }
}
