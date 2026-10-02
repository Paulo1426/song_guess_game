import '../models/partida.dart';

class GameService {
  List<String> audiosDePartida(Partida partida) {
    return partida.instrumentosParaReproducir()
        .map((instrumento) => instrumento.audioUrl)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
  }
}