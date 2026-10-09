import 'package:flutter_test/flutter_test.dart';
import 'package:song_guess_game/models/nivel.dart';
import 'package:song_guess_game/services/firebase_game_repository.dart';

void main() {
  test('retains backend status for actionable error messages', () {
    const error = GameRepositoryException(
      statusCode: 429,
      message: 'Espera 30 segundos antes de volver a intentarlo',
    );

    expect(error.statusCode, 429);
    expect(error.toString(), contains('30 segundos'));
  });

  test('parses previously completed levels as replayable', () {
    final state = EstadoJuegoRemoto.fromJson({
      'dificultades': [
        {
          'dificultad': 'facil',
          'desbloqueada': true,
          'completados': 1,
          'total': 1,
        },
        {
          'dificultad': 'medio',
          'desbloqueada': true,
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
      'dificultad_activa': 'medio',
      'niveles': [],
      'niveles_repetibles': [
        {
          'nivel': {
            'id': 'facil-01',
            'numero': 1,
            'dificultad': 'facil',
            'cancion_id': 'cancion-001',
            'cancion_titulo': 'Canción misteriosa',
            'instrumentos': [
              {'tipo': 'bateria', 'precio': 0, 'audio_url': ''},
              {'tipo': 'bajo', 'precio': 0, 'audio_url': ''},
              {'tipo': 'acordeon', 'precio': 0, 'audio_url': ''},
            ],
            'puntos_inicio': [0],
            'modo_prueba': true,
            'duracion_fragmento_segundos': 20,
          },
          'completado': true,
          'puede_iniciar': true,
        },
      ],
    });

    expect(state.dificultadActiva, Dificultad.medio);
    expect(state.niveles, isEmpty);
    expect(state.nivelesRepetibles, hasLength(1));
    expect(state.nivelesRepetibles.single.completado, isTrue);
    expect(state.nivelesRepetibles.single.nivel.id, 'facil-01');
  });

  test('parses the purchased instrument price for disclosure', () {
    final result = ResultadoCompraInstrumento.fromJson({
      'presupuestoRestante': 600000,
      'instrumentosComprados': ['acordeon'],
      'melodiaDescubierta': false,
      'compraRealizada': true,
      'precioInstrumento': 400000,
    });

    expect(result.precioInstrumento, 400000);
    expect(result.presupuestoRestante, 600000);
  });
}
