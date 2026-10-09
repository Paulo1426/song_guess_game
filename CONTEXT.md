# Contexto del proyecto: Song Guess Game

## Resumen general
Este repositorio corresponde a una aplicación móvil desarrollada en Flutter para un juego de adivinanza musical. La idea principal es que el usuario escuche fragmentos de música divididos por instrumentos (stems) y trate de identificar la canción, el nivel o la estructura correcta en cada partida.

El proyecto combina:
- Frontend en Flutter/Dart
- Estado reactivo con Riverpod
- Firebase Authentication para inicio de sesión
- Cloud Firestore para catálogo y progreso
- Supabase Edge Functions para reglas de juego y autorización
- Supabase Storage para stems y canciones
- Reproducción de audio con just_audio y audio_session

## Stack tecnológico
- Flutter SDK / Dart 3.12+
- flutter_riverpod para manejo de estado
- firebase_core y firebase_auth para Firebase
- cloud_firestore para acceso futuro del cliente; el flujo actual consulta Firestore mediante Edge Functions
- supabase_flutter para almacenamiento/audio y servicios de Supabase existentes
- http para llamadas autenticadas a Edge Functions
- just_audio para reproducción de audio
- audio_session para gestión del audio del sistema
- SQLite no se usa; el progreso actual se conserva en Firestore

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

- Se inicializa Flutter y Firebase para Android e iOS
- Lee `SUPABASE_URL` y `SUPABASE_ANON_KEY` para usar los servicios de Supabase
- Si ambas variables existen, inicializa el cliente de Supabase
- La app se ejecuta con `ProviderScope` para permitir Riverpod
- La vista principal es `HomeScreen` en Android e iOS; Firebase Web no esta
  configurado

## Configuración y secretos
La app requiere configuraciones públicas de Firebase generadas en
`lib/firebase_options.dart` y variables de Supabase para invocar las Edge
Functions. Ejecuta Flutter con valores por `dart-define`:

```powershell
flutter run --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA
```

Importante:
- `SUPABASE_URL` es la URL del proyecto Supabase
- `SUPABASE_ANON_KEY` es la clave pública (anon/publishable)
- La cuenta de servicio Firebase y la clave `service_role` solo viven como
  secretos del backend; nunca se incluyen en Flutter

## Modelo de dominio y persistencia
El proyecto combina servicios según su función. Firebase Authentication
identifica al jugador; Firestore conserva canciones, niveles, orden personal,
partidas y progreso. Supabase Storage guarda los archivos de audio.

### Entidades principales
- `Usuario`: perfil del jugador, progreso y logros
- `Nivel`: información del nivel, dificultad, canción asociada y puntos de inicio
- `Partida`: estado de la sesión de juego
- `Instrumento`: representación de cada stem o pista por instrumento

### Repositorios
El README identifica varios servicios clave:
- `FirebaseGameRepository`: llama al backend de progreso con el ID token de Firebase
- `SupabaseNivelRepository`: adaptador/repositorio heredado del catálogo de Supabase
- `UsuarioRepository`: repositorio heredado de perfiles/progreso en Supabase
- `AudioStorageService`: sube archivos de audio a Supabase Storage
- `AudioService`: prepara los reproductores por instrumento para una partida
- `SupabaseService`: cliente y autenticación heredados de Supabase

## Flujo funcional principal
1. El usuario inicia sesión o se registra con Firebase Authentication.
2. La app llama `game-progress` con un ID token de Firebase.
3. La Edge Function asigna y persiste para ese usuario el orden aleatorio de la dificultad activa.
4. El usuario completa todos los niveles de Fácil para desbloquear Media, y todos los de Media para desbloquear Avanzada.
5. El backend crea partidas, valida la respuesta contra documentos privados y guarda el progreso en Firestore.
6. Los audios se almacenan en Supabase Storage; la futura conexión de reproducción debe obtener enlaces temporales autorizados.

## Audio y stems
La app no separa canciones en tiempo real. Los stems deben prepararse previamente en una herramienta administrativa y luego subirse a Supabase Storage.

Se espera una estructura similar a:
- `cancion-id/bateria.mp3`
- `cancion-id/acordeon.mp3`
- `cancion-id/bajo.mp3`
- `cancion-id/guitarra.mp3`

Reglas relevantes del README:
- Cada stem debe arrancar al mismo instante
- El punto inicial de reproducción debe ser único para toda la partida
- La respuesta melódica debe permanecer en la colección privada de respuestas
- No se modifica la canción original; se usa el stem correspondiente por nivel

## Datos y base de datos
Los archivos SQL de `supabase/` describen el modelo heredado de Supabase:
- usuarios
- perfiles
- canciones
- niveles
- instrumentos
- progreso del jugador
- insignias
- estructuras para la lógica de juego

`supabase/migration_juego.sql` añade fragmentos, partidas y compras al esquema
heredado. El nuevo modelo de Firestore y sus campos están definidos en
`FIREBASE_SETUP.md`. Las respuestas no deben guardarse en documentos legibles
por el cliente.

## Archivos clave para entender el proyecto
- `README.md`: documentación principal
- `pubspec.yaml`: dependencias y configuración del proyecto Flutter
- `lib/main.dart`: punto de entrada de la app
- `lib/screens/home_screen.dart`: pantalla principal
- `lib/screens/game_screen.dart`: experiencia de juego
- `lib/services/supabase_service.dart`: cliente de Supabase
- `lib/services/firebase_game_repository.dart`: llamadas de progreso desde Flutter
- `supabase/functions/game-progress/index.ts`: orden, inicio de nivel y validación de respuesta
- `supabase/functions/audio-link/index.ts`: enlaces temporales de Storage (pendiente de despliegue)
- `FIREBASE_SETUP.md`: esquema, configuración y despliegue
- `lib/services/audio_service.dart`: reproducción modular de audio
- `lib/services/game_service.dart`: lógica del juego
- `lib/services/usuario_repository.dart`: repositorio de usuario
- `lib/services/nivel_repository.dart` y `supabase_nivel_repository.dart`: repositorio de niveles
- `lib/models/*.dart`: modelos del dominio

## Estado del trabajo actual
La app móvil se encuentra en transición de backend. El inicio de sesión y el
flujo básico de progreso usan Firebase y Supabase Edge Functions; aún quedan por
conectar la compra de instrumentos y la reproducción protegida de audios.
La arquitectura mantiene:
- UI en Flutter
- Providers para la lógica reactiva
- Servicios para acceso a Firebase, Supabase y audio
- Modelos de dominio con reglas del juego
- SQL para almacenamiento y datos del juego

El contexto principal es una experiencia musical con cuatro stems por nivel
(Bateria, Acordeon, Bajo y Guitarra), hasta cinco niveles activos por dificultad,
presupuesto de $1.000.000 y maximo tres instrumentos comprados por partida.
En cada partida los cuatro instrumentos estan disponibles y se permiten tres
compras, cuyos precios se asignan al seleccionar y suman exactamente $1.000.000
($400.000, $300.000 y $300.000). Tras la tercera compra, la melodia se asigna al
instrumento no comprado el 70% de las veces, y a uno comprado el 30%; si queda
en uno comprado, se desbloquean los cuatro stems. La progresion conserva orden
personal y desbloqueo secuencial de dificultades.

## Observaciones útiles para continuar el trabajo
- Las claves públicas de Firebase/Supabase pueden estar en el cliente; nunca
  incluyas la cuenta de servicio ni `service_role`
- Los archivos de audio deben prepararse fuera de la app y publicarse en Storage
- La lógica de reproducción debe ser coherente y sincronizada en todos los stems
- El desarrollo de nuevas funcionalidades debe mantener la separación entre UI, repositorios y servicios
- El backend de progresión valida el avance; no confíes en el estado local de
  la interfaz como autorización
