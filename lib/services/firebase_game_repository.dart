import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/nivel.dart';

class NivelAsignado {
  const NivelAsignado({
    required this.nivel,
    required this.completado,
    required this.puedeIniciar,
  });

  final Nivel nivel;
  final bool completado;
  final bool puedeIniciar;

  factory NivelAsignado.fromJson(Map<String, dynamic> json) {
    return NivelAsignado(
      nivel: Nivel.fromJson(json['nivel'] as Map<String, dynamic>),
      completado: json['completado'] as bool? ?? false,
      puedeIniciar: json['puede_iniciar'] as bool? ?? false,
    );
  }
}

class ProgresoDificultadRemoto {
  const ProgresoDificultadRemoto({
    required this.dificultad,
    required this.desbloqueada,
    required this.completados,
    required this.total,
  });

  final Dificultad dificultad;
  final bool desbloqueada;
  final int completados;
  final int total;

  factory ProgresoDificultadRemoto.fromJson(Map<String, dynamic> json) {
    return ProgresoDificultadRemoto(
      dificultad: DificultadExtension.fromId(json['dificultad'] as String),
      desbloqueada: json['desbloqueada'] as bool,
      completados: (json['completados'] as num).toInt(),
      total: (json['total'] as num).toInt(),
    );
  }
}

class EstadoJuegoRemoto {
  const EstadoJuegoRemoto({
    required this.dificultades,
    required this.dificultadActiva,
    required this.niveles,
  });

  final List<ProgresoDificultadRemoto> dificultades;
  final Dificultad dificultadActiva;
  final List<NivelAsignado> niveles;

  factory EstadoJuegoRemoto.fromJson(Map<String, dynamic> json) {
    return EstadoJuegoRemoto(
      dificultades: (json['dificultades'] as List<dynamic>)
          .map(
            (item) =>
                ProgresoDificultadRemoto.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      dificultadActiva: DificultadExtension.fromId(
        json['dificultad_activa'] as String,
      ),
      niveles: (json['niveles'] as List<dynamic>)
          .map((item) => NivelAsignado.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class FirebaseGameRepository {
  FirebaseGameRepository({
    FirebaseAuth? auth,
    http.Client? client,
    String? supabaseUrl,
    String? supabaseAnonKey,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _supabaseUrl =
           supabaseUrl ?? const String.fromEnvironment('SUPABASE_URL'),
       _supabaseAnonKey =
           supabaseAnonKey ?? const String.fromEnvironment('SUPABASE_ANON_KEY');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _supabaseUrl;
  final String _supabaseAnonKey;

  Future<EstadoJuegoRemoto> cargarEstado() async {
    final response = await _post({'action': 'progress'});
    return EstadoJuegoRemoto.fromJson(
      response['estado'] as Map<String, dynamic>,
    );
  }

  Future<String> iniciarNivel(String nivelId) async {
    final response = await _post({'action': 'startLevel', 'levelId': nivelId});
    return response['gameId'] as String;
  }

  Future<bool> enviarRespuesta({
    required String gameId,
    required String respuesta,
  }) async {
    final response = await _post({
      'action': 'submitAnswer',
      'gameId': gameId,
      'answer': respuesta,
    });
    return response['correct'] as bool;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw StateError(
        'Configura SUPABASE_URL y SUPABASE_ANON_KEY con --dart-define.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Inicia sesión con Firebase para continuar.');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase no entregó un token de sesión válido.');
    }

    final response = await _client.post(
      Uri.parse(
        '${_supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/functions/v1/game-progress',
      ),
      headers: {
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta no válida del servicio de juego');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        decoded['error'] as String? ??
            'El servicio de juego respondió ${response.statusCode}.',
      );
    }
    return decoded;
  }
}
