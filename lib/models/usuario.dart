import 'nivel.dart';

class ProgresoDificultad {
  final int nivelActual;
  final Set<int> nivelesCompletados;

  ProgresoDificultad({
    this.nivelActual = 1,
    Iterable<int> nivelesCompletados = const [],
  }) : nivelesCompletados = Set.unmodifiable(nivelesCompletados);

  ProgresoDificultad completar(int nivel) {
    final completados = {...nivelesCompletados, nivel};
    return ProgresoDificultad(
      nivelActual: nivelActual < nivel + 1 ? nivel + 1 : nivelActual,
      nivelesCompletados: completados,
    );
  }

  Map<String, dynamic> toJson() => {
        'nivel_actual': nivelActual,
        'niveles_completados': nivelesCompletados.toList()..sort(),
      };
}

class Usuario {
  final String id;
  final String? email;
  final String? nombre;
  final Map<Dificultad, ProgresoDificultad> progreso;
  final Set<String> insignias;

  Usuario({
    required this.id,
    this.email,
    this.nombre,
    Map<Dificultad, ProgresoDificultad>? progreso,
    Iterable<String> insignias = const [],
  })  : progreso = Map.unmodifiable(progreso ??
            {
              for (final dificultad in Dificultad.values)
                dificultad: ProgresoDificultad(),
            }),
        insignias = Set.unmodifiable(insignias);

  factory Usuario.fromJson(Map<String, dynamic> json) {
      final rawProgreso = json['progreso'] as Map<String, dynamic>? ?? {};
      final parsedProgreso = <Dificultad, ProgresoDificultad>{};
      for (final dificultad in Dificultad.values) {
        final raw = rawProgreso[dificultad.id] as Map<String, dynamic>?;
        parsedProgreso[dificultad] = raw == null
            ? ProgresoDificultad()
            : ProgresoDificultad(
                nivelActual: (raw['nivel_actual'] as num?)?.toInt() ?? 1,
                nivelesCompletados:
                    ((raw['niveles_completados'] as List<dynamic>?) ?? [])
                        .map((nivel) => (nivel as num).toInt()),
              );
      }
      return Usuario(
        id: json['id'] as String,
        email: json['email'] as String?,
        nombre: json['nombre'] as String?,
        progreso: parsedProgreso,
        insignias: ((json['insignias'] as List<dynamic>?) ?? [])
            .map((insignia) => insignia as String),
      );
    }

    Usuario completarNivel(Dificultad dificultad, int nivel) {
      final nuevoProgreso = {
        ...progreso,
        dificultad: (progreso[dificultad] ?? ProgresoDificultad())
            .completar(nivel),
      };
      final nuevasInsignias = {...insignias};
      if (nivel % 5 == 0) {
        nuevasInsignias.add('${dificultad.id}_$nivel');
      }
      return Usuario(
      id: id,
      email: email,
      nombre: nombre,
      progreso: nuevoProgreso,
      insignias: nuevasInsignias,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'nombre': nombre,
        'progreso': {
          for (final entry in progreso.entries) entry.key.id: entry.value.toJson(),
        },
        'insignias': insignias.toList(),
      };
}
