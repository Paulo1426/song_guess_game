import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nivel.dart';
import '../models/usuario.dart';

class UsuarioRepository {
  final SupabaseClient _client;

  UsuarioRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<Usuario> obtener(String userId) async {
    final perfil = await _client
        .from('perfiles')
        .select('id, nombre, email, insignias')
        .eq('id', userId)
        .single();
    final progreso = await _client
        .from('progreso_usuario')
        .select('dificultad, nivel_actual, niveles_completados')
        .eq('usuario_id', userId);
    final progresoMap = <String, dynamic>{};
    for (final row in progreso) {
      progresoMap[row['dificultad'] as String] = {
        'nivel_actual': row['nivel_actual'],
        'niveles_completados': row['niveles_completados'],
      };
    }
    return Usuario.fromJson({...perfil, 'progreso': progresoMap});
  }

  Future<void> guardarProgreso({
    required String userId,
    required Dificultad dificultad,
    required ProgresoDificultad progreso,
  }) async {
    await _client.from('progreso_usuario').upsert({
      'usuario_id': userId,
      'dificultad': dificultad.id,
      'nivel_actual': progreso.nivelActual,
      'niveles_completados': progreso.nivelesCompletados.toList()..sort(),
    });
  }

  Future<void> guardarInsignias({
    required String userId,
    required Iterable<String> insignias,
  }) async {
    await _client
        .from('perfiles')
        .update({'insignias': insignias.toList()}).eq('id', userId);
  }
}
