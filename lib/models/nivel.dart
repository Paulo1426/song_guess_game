import 'dart:math';

import 'instrumento.dart';

enum Dificultad { facil, medio, avanzado }

extension DificultadExtension on Dificultad {
  String get id => name;

  static Dificultad fromId(String value) {
    return Dificultad.values.firstWhere(
      (dificultad) => dificultad.id == value,
      orElse: () => throw FormatException('Dificultad desconocida: $value'),
    );
  }
}

class Nivel {
  static const presupuestoTotal = 2000000;
  static const duracionFragmento = Duration(seconds: 5);
  static const tiposEsperados = TipoInstrumento.values;

  final String id;
  final int numero;
  final Dificultad dificultad;
  final String cancionId;
  final String cancionTitulo;
  final List<Instrumento> instrumentos;
  final TipoInstrumento? instrumentoMelodia;
  final List<int> puntosInicio;

  Nivel({
    required this.id,
    required this.numero,
    required this.dificultad,
    required this.cancionId,
    required this.cancionTitulo,
    required List<Instrumento> instrumentos,
    this.instrumentoMelodia,
    this.puntosInicio = const [],
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
    final unidades = <int>[1, 2, 2, 3, 4, 4, 4]..shuffle(rng);
    final tipos = [...TipoInstrumento.values]..shuffle(rng);
    final instrumentos = [
      for (var i = 0; i < tipos.length; i++)
        Instrumento(
          tipo: tipos[i],
          precio: unidades[i] * 100000,
          audioUrl: audios[tipos[i]] ?? '',
        ),
    ];

    return Nivel(
      id: id,
      numero: numero,
      dificultad: dificultad,
      cancionId: cancionId,
      cancionTitulo: cancionTitulo,
      instrumentos: instrumentos,
      instrumentoMelodia: tipos[rng.nextInt(tipos.length)],
    );
  }

  Instrumento instrumento(TipoInstrumento tipo) =>
      instrumentos.firstWhere((instrumento) => instrumento.tipo == tipo);

  void _validar() {
    if (instrumentos.length != tiposEsperados.length) {
      throw ArgumentError('Cada nivel debe tener exactamente 7 instrumentos');
    }
    if (instrumentos.map((instrumento) => instrumento.tipo).toSet().length !=
        tiposEsperados.length) {
      throw ArgumentError('Los instrumentos de un nivel no pueden repetirse');
    }
    if (instrumentos.fold<int>(0, (total, item) => total + item.precio) !=
        presupuestoTotal) {
      throw ArgumentError('Los precios deben sumar exactamente 2.000.000');
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
  };
}
