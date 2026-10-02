# Contexto del proyecto: Song Guess Game

## Resumen general
Este repositorio corresponde a una aplicación móvil desarrollada en Flutter para un juego de adivinanza musical. La idea principal es que el usuario escuche fragmentos de música divididos por instrumentos (stems) y trate de identificar la canción, el nivel o la estructura correcta en cada partida.

El proyecto combina:
- Frontend en Flutter/Dart
- Estado reactivo con Riverpod
- Backend y autenticación con Supabase
- Reproducción de audio con just_audio y audio_session
- Persistencia de usuarios, niveles, progresos e insignias a través de Supabase

## Stack tecnológico
- Flutter SDK / Dart 3.12+
- flutter_riverpod para manejo de estado
- supabase_flutter para autenticación, base de datos y almacenamiento
- just_audio para reproducción de audio
- audio_session para gestión del audio del sistema
- SQLite no se usa en la app; la lógica de datos principal está en Supabase

## Estructura del proyecto

### Directorio principal
- `lib/`: código fuente de la aplicación
  - `main.dart`: entrada principal de la app
  - `screens/`: pantallas principales (`home_screen.dart`, `game_screen.dart`)
  - `services/`: lógica de negocio y acceso a datos
  - `models/`: entidades del dominio (`usuario`, `partida`, `nivel`, `instrumento`)
  - `data/`: datos estáticos o mock data (`musica.dart`, `insignias.dart`)
  - `providers/`: providers de Riverpod
- `supabase/`: scripts SQL de base de datos y esquema
- `test/`: pruebas de Flutter
- `android/`, `ios/`, `linux/`, `macos/`, `windows/`: configuraciones nativas de la app

## Punto de entrada de la aplicación
El arranque está en `lib/main.dart`.

- Se inicializa Flutter
- Lee las variables de entorno `SUPABASE_URL` y `SUPABASE_ANON_KEY`
- Si existen, se inicializa Supabase con `SupabaseService.initialize(...)`
- La app se ejecuta con `ProviderScope` para permitir Riverpod
- La vista principal es `HomeScreen`

## Configuración crítica de Supabase
La app no debe guardar secretos del backend en el repositorio. La documentación del proyecto recomienda lanzar Flutter con valores por `dart-define`:

```powershell
flutter run --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA
```

Importante:
- `SUPABASE_URL` es la URL del proyecto
- `SUPABASE_ANON_KEY` es la clave pública (anon/publishable)
- Nunca se debe usar `service_role` desde Flutter

## Modelo de dominio y persistencia
El proyecto está pensado alrededor de una lógica de juego musical con datos centralizados en Supabase.

### Entidades principales
- `Usuario`: perfil del jugador, progreso y logros
- `Nivel`: información del nivel, dificultad, canción asociada y puntos de inicio
- `Partida`: estado de la sesión de juego
- `Instrumento`: representación de cada stem o pista por instrumento

### Repositorios
El README identifica varios servicios clave:
- `SupabaseNivelRepository`: consulta niveles y construye URLs públicas de Storage
- `UsuarioRepository`: lee y actualiza perfiles, progreso e insignias
- `AudioStorageService`: sube archivos de audio a Supabase Storage
- `AudioService`: prepara los reproductores por instrumento para una partida
- `SupabaseService`: gestión del cliente y autenticación general

## Flujo funcional principal
1. El usuario inicia sesión o se registra.
2. La base de datos genera automáticamente un perfil y progreso cuando Supabase Auth registra al usuario.
3. La app obtiene niveles y canciones desde Supabase.
4. Para cada nivel, se selecciona un tipo melódico y un punto de inicio.
5. Se cargan y reproducen stems de audio por instrumento.
6. El sistema intenta sincronizar todos los audios desde el mismo punto inicial.
7. El usuario interactúa con la partida y el sistema actualiza progreso, puntos y logros.

## Audio y stems
La app no separa canciones en tiempo real. Los stems deben prepararse previamente en una herramienta administrativa y luego subirse a Supabase Storage.

Se espera una estructura similar a:
- `cancion-id/nivel-01/guitarra.mp3`
- `cancion-id/nivel-01/bajo.mp3`
- `cancion-id/nivel-01/piano.mp3`
- etc.

Reglas relevantes del README:
- Cada stem debe arrancar al mismo instante
- El punto inicial de reproducción debe ser único para toda la partida
- El tipo melódico se elige al crear el nivel
- No se modifica la canción original; se usa el stem correspondiente por nivel

## Base de datos y SQL
El archivo `supabase/schema.sql` define la base de datos del proyecto, incluyendo:
- usuarios
- perfiles
- canciones
- niveles
- instrumentos
- progreso del jugador
- insignias
- estructuras para la lógica de juego

Además existe `supabase/migration_juego.sql`, que parece complementar la migración principal del juego.

## Archivos clave para entender el proyecto
- `README.md`: documentación principal
- `pubspec.yaml`: dependencias y configuración del proyecto Flutter
- `lib/main.dart`: punto de entrada de la app
- `lib/screens/home_screen.dart`: pantalla principal
- `lib/screens/game_screen.dart`: experiencia de juego
- `lib/services/supabase_service.dart`: cliente de Supabase
- `lib/services/audio_service.dart`: reproducción modular de audio
- `lib/services/game_service.dart`: lógica del juego
- `lib/services/usuario_repository.dart`: repositorio de usuario
- `lib/services/nivel_repository.dart` y `supabase_nivel_repository.dart`: repositorio de niveles
- `lib/models/*.dart`: modelos del dominio

## Estado del trabajo actual
Este repositorio está orientado a un proyecto de app móvil en desarrollo con una arquitectura clara en capas:
- UI en Flutter
- Providers para la lógica reactiva
- Servicios para acceso a Supabase y audio
- Modelos de dominio con reglas del juego
- SQL para almacenamiento y datos del juego

El contexto principal es que la app es una experiencia musical interactiva con autenticación, niveles, progresos y reproducción sincronizada de múltiples pistas de audio.

## Observaciones útiles para continuar el trabajo
- La clave pública de Supabase puede ir en la app, pero no la `service_role`
- Los archivos de audio deben prepararse fuera de la app y publicarse en Storage
- La lógica de reproducción debe ser coherente y sincronizada en todos los stems
- El desarrollo de nuevas funcionalidades debe mantener la separación entre UI, repositorios y servicios
- Cuando se revisen cambios, conviene tener en cuenta que la aplicación es en Flutter y que usa Supabase como backend principal
