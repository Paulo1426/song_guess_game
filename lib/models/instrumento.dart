enum TipoInstrumento {
  caja,
  guacharaca,
  acordeon,
  piano,
  guitarra,
  bajo,
  trompeta,
}

extension TipoInstrumentoExtension on TipoInstrumento {
  String get id => name;

  String get nombre {
    switch (this) {
      case TipoInstrumento.caja:
        return 'Caja';
      case TipoInstrumento.guacharaca:
        return 'Guacharaca';
      case TipoInstrumento.acordeon:
        return 'Acordeón';
      case TipoInstrumento.piano:
        return 'Piano';
      case TipoInstrumento.guitarra:
        return 'Guitarra';
      case TipoInstrumento.bajo:
        return 'Bajo';
      case TipoInstrumento.trompeta:
        return 'Trompeta';
    }
  }

  static TipoInstrumento fromId(String value) {
    return TipoInstrumento.values.firstWhere(
      (tipo) => tipo.id == value,
      orElse: () => throw FormatException('Instrumento desconocido: $value'),
    );
  }
}

class Instrumento {
  final TipoInstrumento tipo;
  final int precio;
  final String audioUrl;

  const Instrumento({
    required this.tipo,
    required this.precio,
    required this.audioUrl,
  }) : assert(precio == 100000 ||
            precio == 200000 ||
            precio == 300000 ||
            precio == 400000);

  String get id => tipo.id;
  String get nombre => tipo.nombre;

  factory Instrumento.fromJson(Map<String, dynamic> json) {
    return Instrumento(
      tipo: TipoInstrumentoExtension.fromId(json['tipo'] as String),
      precio: (json['precio'] as num).toInt(),
      audioUrl: json['audio_url'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': id,
        'precio': precio,
        'audio_url': audioUrl,
      };

  Instrumento copyWith({
    TipoInstrumento? tipo,
    int? precio,
    String? audioUrl,
  }) {
    return Instrumento(
      tipo: tipo ?? this.tipo,
      precio: precio ?? this.precio,
      audioUrl: audioUrl ?? this.audioUrl,
    );
  }
}
