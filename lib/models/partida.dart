import 'dart:math';

import 'nivel.dart';
import 'instrumento.dart';

class Partida {
  static const presupuestoInicial = Nivel.presupuestoTotal;
  static const maxInstrumentosComprados = 3;

  final List<Instrumento> instrumentos;
  final Random _random;
  List<TipoInstrumento> comprados;
  Map<TipoInstrumento, int> preciosAsignados;
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
    Random? random,
    Map<TipoInstrumento, int>? preciosAsignados,
  }) : instrumentos = List.unmodifiable(instrumentos),
       _random = random ?? Random(),
       comprados = List.unmodifiable(comprados ?? []),
       preciosAsignados = Map.unmodifiable(preciosAsignados ?? {}) {
    if (presupuestoRestante < 0 || presupuestoRestante > presupuestoInicial) {
      throw ArgumentError('El presupuesto restante no es válido');
    }
  }

  bool comprar(String tipo) =>
      comprarTipo(TipoInstrumentoExtension.fromId(tipo));

  bool comprarTipo(TipoInstrumento tipo) {
    if (ganada || comprados.contains(tipo)) return false;
    if (comprados.length >= maxInstrumentosComprados) return false;
    if (!instrumentos.any((item) => item.tipo == tipo)) {
      throw StateError('El instrumento no pertenece a la partida');
    }
    final precio = _siguientePrecio();
    if (precio > presupuestoRestante) return false;

    presupuestoRestante -= precio;
    preciosAsignados = Map.unmodifiable({...preciosAsignados, tipo: precio});
    comprados = List.unmodifiable([...comprados, tipo]);
    return true;
  }

  int? precioDe(TipoInstrumento tipo) => preciosAsignados[tipo];

  int _siguientePrecio() {
    final totalComprado = preciosAsignados.values.fold<int>(
      0,
      (total, precio) => total + precio,
    );
    if (totalComprado != presupuestoInicial - presupuestoRestante) {
      throw StateError('El saldo no coincide con las compras registradas');
    }
    final restante = presupuestoInicial - totalComprado;
    if (comprados.isEmpty ||
        (comprados.length == 1 && totalComprado == 300000)) {
      return _random.nextBool() ? 400000 : 300000;
    }
    if (comprados.length == 1 && totalComprado == 400000) {
      return 300000;
    }
    return restante;
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
        .fold<int>(
          0,
          (total, instrumento) =>
              total + (preciosAsignados[instrumento.tipo] ?? 0),
        );
    ganada = true;
  }

  Partida copy() => Partida(
    instrumentos: instrumentos,
    presupuestoRestante: presupuestoRestante,
    comprados: comprados,
    preciosAsignados: preciosAsignados,
    melodiaDescubierta: melodiaDescubierta,
    ganada: ganada,
    puntoInicio: puntoInicio,
  );

  Map<String, dynamic> toJson() => {
    'presupuesto_restante': presupuestoRestante,
    'instrumentos_comprados': comprados.map((item) => item.id).toList(),
    'precios_instrumentos': {
      for (final entry in preciosAsignados.entries) entry.key.id: entry.value,
    },
    'melodia_descubierta': melodiaDescubierta,
    'ganada': ganada,
    'punto_inicio': puntoInicio,
  };
}
