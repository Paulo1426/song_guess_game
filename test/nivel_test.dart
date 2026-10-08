import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_guess_game/models/instrumento.dart';
import 'package:song_guess_game/models/nivel.dart';
import 'package:song_guess_game/models/partida.dart';

void main() {
  final instrumentosPrueba = [
    Instrumento(tipo: TipoInstrumento.acordeon, precio: 0, audioUrl: ''),
    Instrumento(tipo: TipoInstrumento.bajo, precio: 0, audioUrl: ''),
    Instrumento(tipo: TipoInstrumento.bateria, precio: 0, audioUrl: ''),
  ];

  Nivel nivelDePrueba({bool modoPrueba = true, int duracion = 20}) => Nivel(
    id: 'facil-01',
    numero: 1,
    dificultad: Dificultad.facil,
    cancionId: 'cancion-001',
    cancionTitulo: 'Canción misteriosa',
    instrumentos: instrumentosPrueba,
    puntosInicio: const [0],
    modoPrueba: modoPrueba,
    duracionFragmentoSegundos: duracion,
  );

  test('acepta tres instrumentos solo en modo de prueba de 20 segundos', () {
    final nivel = nivelDePrueba();

    expect(nivel.instrumentos, hasLength(3));
    expect(nivel.modoPrueba, isTrue);
    expect(nivel.duracionFragmentoSegundos, 20);
  });

  test('rechaza tres instrumentos fuera del modo de prueba', () {
    expect(
      () => nivelDePrueba(modoPrueba: false, duracion: 5),
      throwsArgumentError,
    );
  });

  test('rechaza duración de prueba distinta a 20 segundos', () {
    expect(() => nivelDePrueba(duracion: 5), throwsArgumentError);
  });

  test('usa fragmentos normales de 30 segundos', () {
    final nivel = Nivel.generar(
      id: 'facil-01',
      numero: 1,
      dificultad: Dificultad.facil,
      cancionId: 'cancion-001',
      cancionTitulo: 'Canción misteriosa',
      audios: const {},
    );

    expect(nivel.duracionFragmentoSegundos, 30);
    expect(Nivel.duracionFragmento, const Duration(seconds: 30));
    expect(
      () => Nivel(
        id: 'facil-01',
        numero: 1,
        dificultad: Dificultad.facil,
        cancionId: 'cancion-001',
        cancionTitulo: 'Canción misteriosa',
        instrumentos: [
          Instrumento(
            tipo: TipoInstrumento.acordeon,
            precio: 300000,
            audioUrl: '',
          ),
          Instrumento(
            tipo: TipoInstrumento.bateria,
            precio: 400000,
            audioUrl: '',
          ),
          Instrumento(tipo: TipoInstrumento.bajo, precio: 300000, audioUrl: ''),
          Instrumento(
            tipo: TipoInstrumento.guitarra,
            precio: 0,
            audioUrl: '',
            comprable: false,
          ),
        ],
        duracionFragmentoSegundos: 5,
      ),
      throwsArgumentError,
    );
  });

  test('rechaza precios preasignados en el documento del nivel', () {
    expect(
      () => Nivel(
        id: 'facil-01',
        numero: 1,
        dificultad: Dificultad.facil,
        cancionId: 'cancion-001',
        cancionTitulo: 'Canción misteriosa',
        instrumentos: [
          Instrumento(
            tipo: TipoInstrumento.acordeon,
            precio: 400000,
            audioUrl: '',
          ),
          Instrumento(tipo: TipoInstrumento.bateria, precio: 0, audioUrl: ''),
          Instrumento(tipo: TipoInstrumento.bajo, precio: 0, audioUrl: ''),
          Instrumento(tipo: TipoInstrumento.guitarra, precio: 0, audioUrl: ''),
        ],
        puntosInicio: const [0],
      ),
      throwsArgumentError,
    );
  });

  test('normaliza niveles antiguos con precios asignados al parsearlos', () {
    final nivel = Nivel.fromJson({
      'id': 'facil-02',
      'numero': 2,
      'dificultad': 'facil',
      'cancion_id': 'cancion-002',
      'cancion_titulo': 'Canción misteriosa',
      'instrumentos': [
        {
          'tipo': 'bateria',
          'precio': 400000,
          'audio_url': 'cancion-002/track.mp3',
        },
        {
          'tipo': 'acordeon',
          'precio': 300000,
          'audio_url': 'cancion-002/track.mp3',
        },
        {
          'tipo': 'bajo',
          'precio': 300000,
          'audio_url': 'cancion-002/track.mp3',
        },
        {'tipo': 'guitarra', 'precio': 0, 'audio_url': 'cancion-002/track.mp3'},
      ],
    });

    expect(nivel.instrumentos.every((item) => item.precio == 0), isTrue);
    expect(nivel.instrumentos.every((item) => item.comprable), isTrue);
  });

  test('genera cuatro instrumentos disponibles sin asignar precios', () {
    final nivel = Nivel.generar(
      id: 'facil-02',
      numero: 2,
      dificultad: Dificultad.facil,
      cancionId: 'cancion-002',
      cancionTitulo: 'Canción misteriosa',
      audios: const {},
    );

    expect(nivel.instrumentos, hasLength(4));
    expect(nivel.instrumentos.where((item) => item.comprable), hasLength(4));
    expect(nivel.instrumentos.every((item) => item.precio == 0), isTrue);
    expect(nivel.instrumentoMelodia, isNull);
  });

  test('permite comprar como máximo tres instrumentos por partida', () {
    final partida = Partida(
      random: Random(0),
      instrumentos: [
        for (final tipo in TipoInstrumento.values)
          Instrumento(tipo: tipo, precio: 0, audioUrl: '', comprable: true),
      ],
    );

    expect(partida.comprarTipo(TipoInstrumento.bateria), isTrue);
    expect(partida.comprarTipo(TipoInstrumento.acordeon), isTrue);
    expect(partida.comprarTipo(TipoInstrumento.bajo), isTrue);
    expect(partida.comprarTipo(TipoInstrumento.guitarra), isFalse);
    expect(partida.comprados, hasLength(3));
    expect(partida.presupuestoRestante, 0);
    expect(
      partida.preciosAsignados.values.fold<int>(0, (sum, price) => sum + price),
      Nivel.presupuestoTotal,
    );
    expect(
      partida.preciosAsignados.values.where((price) => price == 400000),
      hasLength(1),
    );
    expect(
      partida.preciosAsignados.values.where((price) => price == 300000),
      hasLength(2),
    );
  });

  test('todos los órdenes de precio permiten gastar exactamente el millón', () {
    for (var seed = 0; seed < 20; seed++) {
      final partida = Partida(
        random: Random(seed),
        instrumentos: [
          for (final tipo in TipoInstrumento.values)
            Instrumento(tipo: tipo, precio: 0, audioUrl: ''),
        ],
      );

      for (final tipo in TipoInstrumento.values.take(3)) {
        expect(partida.comprarTipo(tipo), isTrue);
      }
      expect(partida.presupuestoRestante, 0);
      expect(
        partida.preciosAsignados.values.fold<int>(
          0,
          (sum, price) => sum + price,
        ),
        Nivel.presupuestoTotal,
      );
    }
  });

  test('normaliza espacios sobrantes en el identificador de dificultad', () {
    expect(DificultadExtension.fromId('facil \n'), Dificultad.facil);
  });
}
