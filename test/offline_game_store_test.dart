import 'package:flutter_test/flutter_test.dart';
import 'package:song_guess_game/models/instrumento.dart';
import 'package:song_guess_game/models/nivel.dart';
import 'package:song_guess_game/services/offline_game_store.dart';

void main() {
  final level = Nivel(
    id: 'facil-01',
    numero: 1,
    dificultad: Dificultad.facil,
    cancionId: 'cancion-001',
    cancionTitulo: 'Canción misteriosa',
    instrumentos: [
      for (final type in TipoInstrumento.values)
        Instrumento(tipo: type, precio: 0, audioUrl: ''),
    ],
  );

  OfflineLevelData offlineLevel() => OfflineLevelData(
    nivel: level,
    completado: false,
    puedeIniciar: true,
    respuesta: 'cancion misteriosa',
    audioPaths: const {'bateria': 'cache/bateria.mp3'},
    instrumentalAudioPath: 'cache/cancion-instrumental.mp3',
  );

  Map<String, dynamic> levelEntry(Nivel nivel, {required bool completed}) => {
    'nivel': nivel.toJson(),
    'completado': completed,
    'puede_iniciar': !completed,
  };

  OfflineGameSnapshot snapshot({
    required List<Map<String, dynamic>> activeLevels,
    List<Map<String, dynamic>> replayLevels = const [],
  }) => OfflineGameSnapshot(
    uid: 'user-1',
    guest: false,
    stateJson: {
      'dificultades': [
        {
          'dificultad': 'facil',
          'desbloqueada': true,
          'completados': 0,
          'total': activeLevels.length,
        },
        {
          'dificultad': 'medio',
          'desbloqueada': false,
          'completados': 0,
          'total': 0,
        },
        {
          'dificultad': 'avanzado',
          'desbloqueada': false,
          'completados': 0,
          'total': 0,
        },
      ],
      'dificultad_activa': 'facil',
      'niveles': activeLevels,
      'niveles_repetibles': replayLevels,
    },
    levels: [offlineLevel()],
    pendingCompletions: const [],
  );

  test('normalizes accents, case, and punctuation in offline answers', () {
    expect(
      OfflineGameStore.normalizeAnswer('  CANCIÓN   misteriosa! '),
      'cancion misteriosa',
    );
  });

  test('completion unlocks the next level and survives serialization', () {
    final secondLevel = Nivel(
      id: 'facil-02',
      numero: 2,
      dificultad: Dificultad.facil,
      cancionId: 'cancion-002',
      cancionTitulo: 'Otra canción',
      instrumentos: level.instrumentos,
    );
    final initial = snapshot(
      activeLevels: [
        levelEntry(level, completed: false),
        levelEntry(secondLevel, completed: false),
      ],
    );

    final completed = initial.completedLocally(level.id, 'Canción misteriosa');
    final restored = OfflineGameSnapshot.fromJson(completed.toJson());

    expect(restored.estado.niveles.first.completado, isTrue);
    expect(restored.estado.niveles.last.puedeIniciar, isTrue);
    expect(restored.estado.dificultades.first.completados, 1);
    expect(restored.levels.single.completado, isTrue);
    expect(restored.pendingCompletions, [
      {'levelId': level.id, 'answer': 'Canción misteriosa'},
    ]);
    expect(restored.levels.single.audioPaths['bateria'], 'cache/bateria.mp3');
    expect(
      restored.levels.single.instrumentalAudioPath,
      'cache/cancion-instrumental.mp3',
    );
  });

  test(
    'replaying a completed level does not change active difficulty count',
    () {
      final replay = levelEntry(level, completed: true);
      final initial = snapshot(activeLevels: [], replayLevels: [replay]);

      final completed = initial.completedLocally(
        level.id,
        'Canción misteriosa',
      );

      expect(completed.estado.nivelesRepetibles.single.completado, isTrue);
      expect(completed.estado.dificultades.first.completados, 0);
    },
  );
}
