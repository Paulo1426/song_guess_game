# Song Guess Game

## Estado actual

La app usa Firebase Authentication para el inicio de sesion, Firestore para el
catalogo seguro y el progreso, y Supabase Edge Functions para asignar el orden
personal de niveles y validar respuestas. Supabase Storage queda destinado a los
stems y canciones completas.

La guia de configuracion, estructura de documentos, secretos del backend y
despliegue esta en [FIREBASE_SETUP.md](./FIREBASE_SETUP.md).

Para desplegar el backend, configura sus secretos de Firebase/Supabase en
Supabase Dashboard y desde la raiz del proyecto ejecuta:

```powershell
supabase login
supabase link --project-ref TU_PROJECT_REF
supabase functions deploy game-progress
supabase functions deploy audio-link
```

Para ejecutar Flutter, pasa la URL y la clave anon publica de Supabase:

```powershell
flutter run --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA
```

La app no permite acceso al juego hasta tener niveles publicados en Firestore
con el formato descrito en `FIREBASE_SETUP.md`. Mantén la respuesta de cada
cancion en `privateLevelAnswers`, nunca dentro del documento de nivel.
