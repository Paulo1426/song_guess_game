# Song Guess Game

## Configurar Supabase

1. Crea un proyecto en Supabase.
2. Abre **SQL Editor**, pega y ejecuta [`supabase/schema.sql`](./supabase/schema.sql).
3. En **Project Settings > API**, copia la URL y la clave publica (`anon`/publishable key).
4. Ejecuta Flutter sin guardar las claves en el repositorio:

```powershell
flutter run --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA
```

La clave publica puede estar en la app; nunca uses la `service_role` en Flutter.

## Registro e inicio de sesión

El cliente de Supabase esta en `lib/services/supabase_service.dart`.

```dart
final auth = AuthService();
await auth.registrar(
  email: 'usuario@correo.com',
  password: 'UnaClaveSegura123!',
  nombre: 'Jugador',
);
await auth.iniciarSesion(
  email: 'usuario@correo.com',
  password: 'UnaClaveSegura123!',
);
```

El trigger de `schema.sql` crea automaticamente el perfil y las tres filas de
progreso cuando Supabase Auth registra un usuario.

## Preparar y subir audio

La app no separa canciones en tiempo real. Los stems deben prepararse una sola
vez en un equipo de administracion. Para una cancion, exporta un fragmento de
cinco segundos por instrumento:

```text
caja.mp3
guacharaca.mp3
acordeon.mp3
piano.mp3
guitarra.mp3
bajo.mp3
trompeta.mp3
```

Todos deben comenzar en el mismo instante. Si el instrumento melodico cambia por
nivel, se elige el stem correspondiente al crear el nivel; no se modifica la
cancion original.

En el dashboard de Supabase:

1. Abre **Storage** y confirma el bucket publico `instrumentos` creado por el SQL.
2. Sube los archivos con rutas como
   `cancion-id/nivel-01/guitarra.mp3`.
3. Inserta en `canciones` el titulo y artista.
4. Inserta en `niveles` el nivel, dificultad, cancion, puntos de inicio y el
   tipo melodico elegido al azar.
5. Inserta sus siete filas en `nivel_instrumentos`, usando el mismo `audio_path`
   que la ruta del bucket.

Para subir archivos desde una herramienta administrativa Dart, usa
`AudioStorageService.subir`. No expongas una clave `service_role` en la app;
para cargas administrativas utiliza el dashboard o un script privado.

## Repositorios y reproduccion

- `SupabaseNivelRepository` consulta niveles y construye las URLs publicas de
  Storage.
- `UsuarioRepository` lee y actualiza perfiles, progreso e insignias.
- `AudioService` prepara un `AudioPlayer` por stem, busca todos al mismo punto
  inicial, inicia los reproductores y los detiene a los cinco segundos.

El punto inicial debe ser uno solo para todos los instrumentos de una partida.
Selecciona uno de `puntos_inicio` y pásalo a `AudioService.reproducir`; nunca
elijas un punto distinto por instrumento.
