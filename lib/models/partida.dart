import 'nivel.dart';
import 'instrumento.dart';

class Partida {
  static const presupuestoInicial = Nivel.presupuestoTotal;

  final List<Instrumento> instrumentos;
  List<TipoInstrumento> comprados;
  int presupuestoRestante;
  bool melodiaDescubierta;
  bool ganada;
  int? puntoInicio;

  Partida({
    required List<Instrumento> instrumentos,
    this.presupuestoRestante = presupuestoInicial,
    List<TipoInstrumento>? comprados,
    this.melodiaDescubierta = false,
    this.ganada = false,
    this.puntoInicio,
  })  : instrumentos = List.unmodifiable(instrumentos),
        comprados = List.unmodifiable(comprados ?? []) {
    if (presupuestoRestante < 0 || presupuestoRestante > presupuestoInicial) {
      throw ArgumentError('El presupuesto restante no es válido');
    }
  }

  bool comprar(String tipo) => comprarTipo(TipoInstrumentoExtension.fromId(tipo));

  bool comprarTipo(TipoInstrumento tipo) {
    if (ganada || comprados.contains(tipo)) return false;
    final instrumento = instrumentos.firstWhere(
      (item) => item.tipo == tipo,
      orElse: () => throw StateError('El instrumento no pertenece a la partida'),
    );
    if (instrumento.precio > presupuestoRestante) return false;

    presupuestoRestante -= instrumento.precio;
    comprados = List.unmodifiable([...comprados, tipo]);
    return true;
  }

  List<Instrumento> instrumentosParaReproducir() {
    if (melodiaDescubierta) return instrumentos;
    return instrumentos
        .where((instrumento) => comprados.contains(instrumento.tipo))
        .toList(growable: false);
  }

  void descubrirMelodia(TipoInstrumento tipoMelodia) {
    if (comprados.contains(tipoMelodia)) melodiaDescubierta = true;
  }

  void acertar() {
    if (ganada) return;
    presupuestoRestante += instrumentos
        .where((instrumento) => comprados.contains(instrumento.tipo))
        .fold<int>(0, (total, instrumento) => total + instrumento.precio);
    ganada = true;
  }

  Partida copy() => Partida(
        instrumentos: instrumentos,
        presupuestoRestante: presupuestoRestante,
        comprados: comprados,
        melodiaDescubierta: melodiaDescubierta,
        ganada: ganada,
        puntoInicio: puntoInicio,
      );

  Map<String, dynamic> toJson() => {
        'presupuesto_restante': presupuestoRestante,
        'instrumentos_comprados': comprados.map((item) => item.id).toList(),
        'melodia_descubierta': melodiaDescubierta,
        'ganada': ganada,
        'punto_inicio': puntoInicio,
      };
}
