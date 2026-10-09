import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/nivel.dart';
import 'firebase_game_repository.dart';

class OfflineLevelData {
  const OfflineLevelData({
    required this.nivel,
    required this.completado,
    required this.puedeIniciar,
    required this.respuesta,
    required this.audioPaths,
    this.instrumentalAudioPath,
  });

  final Nivel nivel;
  final bool completado;
  final bool puedeIniciar;
  final String respuesta;
  final Map<String, String> audioPaths;
  final String? instrumentalAudioPath;

  factory OfflineLevelData.fromJson(Map<String, dynamic> json) {
    final entry = json['entry'] as Map<String, dynamic>;
    final audioPaths = (json['audioPaths'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );
    return OfflineLevelData(
      nivel: Nivel.fromJson(entry['nivel'] as Map<String, dynamic>),
      completado: entry['completado'] as bool? ?? false,
      puedeIniciar: entry['puede_iniciar'] as bool? ?? false,
      respuesta: entry['respuesta'] as String,
      audioPaths: Map.unmodifiable(audioPaths),
      instrumentalAudioPath: json['instrumentalAudioPath'] as String?,
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> entry) => {
    'entry': entry,
    'audioPaths': audioPaths,
    if (instrumentalAudioPath != null)
      'instrumentalAudioPath': instrumentalAudioPath,
  };

  OfflineLevelData copyWith({bool? completado, bool? puedeIniciar}) =>
      OfflineLevelData(
        nivel: nivel,
        completado: completado ?? this.completado,
        puedeIniciar: puedeIniciar ?? this.puedeIniciar,
        respuesta: respuesta,
        audioPaths: audioPaths,
        instrumentalAudioPath: instrumentalAudioPath,
      );
}

class OfflineGameSnapshot {
  const OfflineGameSnapshot({
    required this.uid,
    required this.guest,
    required this.stateJson,
    required this.levels,
    required this.pendingCompletions,
  });

  final String uid;
  final bool guest;
  final Map<String, dynamic> stateJson;
  final List<OfflineLevelData> levels;
  final List<Map<String, String>> pendingCompletions;

  EstadoJuegoRemoto get estado => EstadoJuegoRemoto.fromJson(stateJson);

  factory OfflineGameSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => OfflineGameSnapshot(
    uid: json['uid'] as String,
    guest: json['guest'] as bool,
    stateJson: Map<String, dynamic>.from(json['state'] as Map),
    levels: (json['levels'] as List<dynamic>)
        .map(
          (item) =>
              OfflineLevelData.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    pendingCompletions: (json['pendingCompletions'] as List<dynamic>)
        .map((item) => Map<String, String>.from(item as Map))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'guest': guest,
    'state': stateJson,
    'levels': [for (final level in levels) level.toJson(_entryJson(level))],
    'pendingCompletions': pendingCompletions,
  };

  OfflineGameSnapshot withState(Map<String, dynamic> state) =>
      OfflineGameSnapshot(
        uid: uid,
        guest: guest,
        stateJson: state,
        levels: levels,
        pendingCompletions: pendingCompletions,
      );

  OfflineGameSnapshot completedLocally(String levelId, String answer) {
    final levelsUpdated = levels
        .map((item) {
          if (item.nivel.id == levelId) {
            return item.copyWith(completado: true, puedeIniciar: true);
          }
          return item;
        })
        .toList(growable: false);
    final state = Map<String, dynamic>.from(stateJson);
    final entries = (state['niveles'] as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    var index = entries.indexWhere(
      (entry) => (entry['nivel'] as Map<String, dynamic>)['id'] == levelId,
    );
    final isReplay = index < 0;
    if (isReplay) {
      final replayEntries = (state['niveles_repetibles'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      index = replayEntries.indexWhere(
        (entry) => (entry['nivel'] as Map<String, dynamic>)['id'] == levelId,
      );
      if (index >= 0) {
        replayEntries[index] = {
          ...replayEntries[index],
          'completado': true,
          'puede_iniciar': true,
        };
        state['niveles_repetibles'] = replayEntries;
      }
    } else {
      entries[index] = {
        ...entries[index],
        'completado': true,
        'puede_iniciar': true,
      };
      final next = entries.indexWhere((entry) => entry['completado'] != true);
      if (next >= 0) {
        entries[next] = {...entries[next], 'puede_iniciar': true};
      }
      state['niveles'] = entries;
    }
    if (index < 0) {
      throw StateError('El nivel offline no pertenece al estado guardado');
    }

    if (!isReplay) {
      final completedCount = entries
          .where((entry) => entry['completado'] == true)
          .length;
      final difficulty = state['dificultad_activa'];
      final summaries = (state['dificultades'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      final summaryIndex = summaries.indexWhere(
        (item) => item['dificultad'] == difficulty,
      );
      if (summaryIndex >= 0) {
        summaries[summaryIndex] = {
          ...summaries[summaryIndex],
          'completados': completedCount,
        };
      }
      state['dificultades'] = summaries;
    }

    final pending = [...pendingCompletions];
    if (!pending.any((item) => item['levelId'] == levelId)) {
      pending.add({'levelId': levelId, 'answer': answer});
    }
    return OfflineGameSnapshot(
      uid: uid,
      guest: guest,
      stateJson: state,
      levels: levelsUpdated,
      pendingCompletions: pending,
    );
  }

  OfflineGameSnapshot withoutPendingCompletion(String levelId) =>
      OfflineGameSnapshot(
        uid: uid,
        guest: guest,
        stateJson: stateJson,
        levels: levels,
        pendingCompletions: pendingCompletions
            .where((item) => item['levelId'] != levelId)
            .toList(growable: false),
      );

  static Map<String, dynamic> _entryJson(OfflineLevelData level) {
    final stateData = level;
    return {
      'nivel': stateData.nivel.toJson(),
      'completado': stateData.completado,
      'puede_iniciar': stateData.puedeIniciar,
      'respuesta': stateData.respuesta,
    };
  }
}

class OfflineGameStore {
  Future<File> _file(String uid) async {
    final directory = await getApplicationSupportDirectory();
    final store = Directory('${directory.path}/offline_game');
    await store.create(recursive: true);
    final safeUid = base64Url.encode(utf8.encode(uid)).replaceAll('=', '');
    return File('${store.path}/$safeUid.json');
  }

  Future<void> save(OfflineGameSnapshot snapshot) async {
    final file = await _file(snapshot.uid);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()));
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<OfflineGameSnapshot?> load(String uid) async {
    final file = await _file(uid);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic> || json['uid'] != uid) {
        throw const FormatException('El perfil offline guardado no es válido');
      }
      return OfflineGameSnapshot.fromJson(json);
    } on FormatException {
      rethrow;
    } on TypeError catch (error) {
      throw FormatException('El perfil offline guardado no es válido: $error');
    }
  }

  static String normalizeAnswer(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
