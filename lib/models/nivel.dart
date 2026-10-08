import 'dart:math';

import 'instrumento.dart';

enum Dificultad { facil, medio, avanzado }

extension DificultadExtension on Dificultad {
  String get id => name;

  static Dificultad fromId(String value) {
    final normalizedValue = value.trim();
    return Dificultad.values.firstWhere(
      (dificultad) => dificultad.id == normalizedValue,
      orElse: () =>
          throw FormatException('Dificultad desconocida: $normalizedValue'),
    );
  }
}

class Nivel {
  static const presupuestoTotal = 1000000;
  static const duracionFragmento = Duration(seconds: 30);
  static const tiposEsperados = TipoInstrumento.values;

  final String id;
  final int numero;
  final Dificultad dificultad;
  final String cancionId;
  final String cancionTitulo;
  final List<Instrumento> instrumentos;
  final TipoInstrumento? instrumentoMelodia;
  final List<int> puntosInicio;
  final bool modoPrueba;
  final int duracionFragmentoSegundos;

  Nivel({
    required this.id,
    required this.numero,
    required this.dificultad,
    required this.cancionId,
    required this.cancionTitulo,
    required List<Instrumento> instrumentos,
    this.instrumentoMelodia,
    this.puntosInicio = const [],
    this.modoPrueba = false,
    this.duracionFragmentoSegundos = 30,
  }) : instrumentos = List.unmodifiable(instrumentos) {
    _validar();
  }

  factory Nivel.generar({
    required String id,
    required int numero,
    required Dificultad dificultad,
    required String cancionId,
    required String cancionTitulo,
    required Map<TipoInstrumento, String> audios,
    Random? random,
  }) {
    final rng = random ?? Random();
    final tipos = [...TipoInstrumento.values]..shuffle(rng);
    final instrumentos = [
      for (final tipo in tipos)
        Instrumento(
          tipo: tipo,
          precio: 0,
          audioUrl: audios[tipo] ?? '',
          comprable: true,
        ),
    ];

    return Nivel(
      id: id,
      numero: numero,
      dificultad: dificultad,
      cancionId: cancionId,
      cancionTitulo: cancionTitulo,
      instrumentos: instrumentos,
    );
  }

  Instrumento instrumento(TipoInstrumento tipo) =>
      instrumentos.firstWhere((instrumento) => instrumento.tipo == tipo);

  void _validar() {
    final cantidadEsperada = modoPrueba ? 3 : tiposEsperados.length;
    if (instrumentos.length != cantidadEsperada) {
      throw ArgumentError(
        modoPrueba
            ? 'Un nivel de prueba debe tener exactamente 3 instrumentos'
            : 'Cada nivel debe tener exactamente 4 instrumentos',
      );
    }
    if (instrumentos.map((instrumento) => instrumento.tipo).toSet().length !=
        instrumentos.length) {
      throw ArgumentError('Los instrumentos de un nivel no pueden repetirse');
    }
    if (!instrumentos.any((item) => item.tipo == TipoInstrumento.acordeon) ||
        !instrumentos.any((item) => item.tipo == TipoInstrumento.bateria)) {
      throw ArgumentError('Cada nivel debe incluir acordeón y batería');
    }
    if (instrumentos.any(
      (instrumento) => instrumento.precio != 0 || !instrumento.comprable,
    )) {
      throw ArgumentError(
        'Los instrumentos de un nivel deben estar disponibles sin precio asignado',
      );
    }
    if (duracionFragmentoSegundos != (modoPrueba ? 20 : 30)) {
      throw ArgumentError(
        modoPrueba
            ? 'Los fragmentos de prueba deben durar 20 segundos'
            : 'Los fragmentos normales deben durar 30 segundos',
      );
    }
    if (instrumentoMelodia != null &&
        !instrumentos.any((item) => item.tipo == instrumentoMelodia)) {
      throw ArgumentError('El instrumento melódico debe pertenecer al nivel');
    }
  }

  factory Nivel.fromJson(Map<String, dynamic> json) {
    final rawInstrumentos = json['instrumentos'] as List<dynamic>;
    return Nivel(
      id: json['id'] as String,
      numero: (json['numero'] as num).toInt(),
      dificultad: DificultadExtension.fromId(json['dificultad'] as String),
      cancionId: json['cancion_id'] as String,
      cancionTitulo: json['cancion_titulo'] as String,
      instrumentos: rawInstrumentos
          .map((item) => Instrumento.fromJson(item as Map<String, dynamic>))
          .toList(),
      instrumentoMelodia: json['instrumento_melodia'] == null
          ? null
          : TipoInstrumentoExtension.fromId(
              json['instrumento_melodia'] as String,
            ),
      puntosInicio: (json['puntos_inicio'] as List<dynamic>? ?? [])
          .map((item) => (item as num).toInt())
          .toList(),
      modoPrueba: json['modo_prueba'] as bool? ?? false,
      duracionFragmentoSegundos:
          (json['duracion_fragmento_segundos'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'numero': numero,
    'dificultad': dificultad.id,
    'cancion_id': cancionId,
    'cancion_titulo': cancionTitulo,
    'instrumentos': instrumentos.map((item) => item.toJson()).toList(),
    if (instrumentoMelodia != null)
      'instrumento_melodia': instrumentoMelodia!.id,
    'puntos_inicio': puntosInicio,
    'modo_prueba': modoPrueba,
    'duracion_fragmento_segundos': duracionFragmentoSegundos,
  };
}
