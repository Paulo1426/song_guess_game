import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/nivel.dart';

class GameRepositoryException implements Exception {
  const GameRepositoryException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

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

class PartidaIniciada {
  const PartidaIniciada({required this.gameId, required this.nivel});

  final String gameId;
  final Nivel nivel;
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
    required this.nivelesRepetibles,
  });

  final List<ProgresoDificultadRemoto> dificultades;
  final Dificultad dificultadActiva;
  final List<NivelAsignado> niveles;
  final List<NivelAsignado> nivelesRepetibles;

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
      nivelesRepetibles: (json['niveles_repetibles'] as List<dynamic>? ?? [])
          .map((item) => NivelAsignado.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class ResultadoCompraInstrumento {
  const ResultadoCompraInstrumento({
    required this.presupuestoRestante,
    required this.instrumentosComprados,
    required this.melodiaDescubierta,
    required this.compraRealizada,
    required this.precioInstrumento,
  });

  final int presupuestoRestante;
  final List<String> instrumentosComprados;
  final bool melodiaDescubierta;
  final bool compraRealizada;
  final int precioInstrumento;

  factory ResultadoCompraInstrumento.fromJson(Map<String, dynamic> json) =>
      ResultadoCompraInstrumento(
        presupuestoRestante: (json['presupuestoRestante'] as num).toInt(),
        instrumentosComprados: (json['instrumentosComprados'] as List<dynamic>)
            .cast<String>(),
        melodiaDescubierta: json['melodiaDescubierta'] as bool,
        compraRealizada: json['compraRealizada'] as bool,
        precioInstrumento: (json['precioInstrumento'] as num).toInt(),
      );
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

  Future<Map<String, dynamic>> descargarPaqueteOffline() async {
    final response = await _post({'action': 'offlineBundle'});
    final bundle = response['bundle'];
    if (bundle is! Map<String, dynamic>) {
      throw const FormatException('El servicio no devolvió el paquete offline');
    }
    return bundle;
  }

  Future<void> sincronizarNivelOffline({
    required String levelId,
    required String respuesta,
  }) async {
    await _post({
      'action': 'completeOfflineLevel',
      'levelId': levelId,
      'answer': respuesta,
    });
  }

  Future<PartidaIniciada> iniciarNivel(String nivelId) async {
    final response = await _post({'action': 'startLevel', 'levelId': nivelId});
    return PartidaIniciada(
      gameId: response['gameId'] as String,
      nivel: Nivel.fromJson(response['nivel'] as Map<String, dynamic>),
    );
  }

  Future<void> finalizarSesionInvitado() async {
    await _post({'action': 'endGuestSession'});
  }

  Future<void> iniciarSesionInvitado() async {
    await _post({'action': 'startGuestSession'});
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

  Future<ResultadoCompraInstrumento> comprarInstrumento({
    required String gameId,
    required String instrumento,
  }) async {
    final response = await _post({
      'action': 'purchaseInstrument',
      'gameId': gameId,
      'instrument': instrumento,
    });
    return ResultadoCompraInstrumento.fromJson(response);
  }

  Future<String> obtenerUrlAudio({
    required String gameId,
    required String tipo,
    String? instrumento,
  }) async {
    final response = await _post({
      'gameId': gameId,
      'type': tipo,
      'instrument': instrumento,
    }, functionName: 'audio-link');
    final url = response['url'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('El servicio no devolvió una URL de audio');
    }
    return url;
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body, {
    String functionName = 'game-progress',
  }) async {
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
        '/functions/v1/$functionName',
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
      throw GameRepositoryException(
        statusCode: response.statusCode,
        message:
            decoded['error'] as String? ??
            'El servicio de juego respondió ${response.statusCode}.',
      );
    }
    return decoded;
  }
}
