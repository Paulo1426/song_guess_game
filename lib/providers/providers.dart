import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nivel.dart';
import '../models/partida.dart';
import '../models/usuario.dart';
import '../services/audio_service.dart';
import '../services/game_service.dart';
import '../services/nivel_repository.dart';
import '../services/validation_service.dart';

final gameServiceProvider = Provider((ref) => GameService());
final audioServiceProvider = Provider((ref) => AudioService());

final nivelRepositoryProvider = Provider<NivelRepository>(
  (ref) => SupabaseNivelRepositoryAdapter(),
);

final validationServiceProvider = Provider<ValidationService>(
  (ref) => LocalValidationService(
    (nivelId) async =>
        (await ref.read(nivelRepositoryProvider).obtener(nivelId)).cancionTitulo,
  ),
);

final usuarioProvider = StateProvider<Usuario>((ref) => Usuario(id: 'local'));

final nivelesProvider = FutureProvider.family<List<Nivel>, Dificultad>(
  (ref, d) => ref.watch(nivelRepositoryProvider).nivelesDe(d),
);

final partidaProvider =
    StateNotifierProvider<PartidaNotifier, Partida?>((ref) => PartidaNotifier());

class PartidaNotifier extends StateNotifier<Partida?> {
  PartidaNotifier() : super(null);

  void iniciar(Nivel nivel) =>
      state = Partida(instrumentos: nivel.instrumentos);

  bool comprar(String tipo) {
    if (state == null) return false;
    final ok = state!.comprar(tipo);
    if (ok) state = state!.copy();
    return ok;
  }

  void acertar() {
    final partida = state;
    if (partida == null) return;
    partida.acertar();
    state = partida.copy();
  }
}