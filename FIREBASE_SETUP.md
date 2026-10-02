# Configuracion inicial de Firebase

Esta guia prepara Firebase junto al estado actual de Song Guess Game. La app
todavia usa Supabase; estos pasos configuran Firebase en paralelo, no migran ni
eliminan datos de Supabase.

## 1. Identificadores de las aplicaciones

El repositorio ya tiene estos identificadores:

- Android: `com.example.song_guess_game`
- iOS: `com.example.songGuessGame`
- Web: aun no tiene un identificador Firebase

Si quieres publicar la app con otro identificador, cambialo primero en el
proyecto Flutter y usa el mismo valor al registrar la app en Firebase. El ID de
Firebase de una app registrada no se puede renombrar luego.

En Firebase Console, abre **Configuracion del proyecto > Tus aplicaciones** y
registra Android e iOS con esos IDs. Si tambien vas a probar la version web,
registra una app Web. FlutterFire puede crear las entradas que falten cuando
ejecutes la configuracion interactiva.

## 2. Habilitar los productos Firebase

En el mismo proyecto Firebase:

1. En **Authentication > Comenzar**, habilita el proveedor **Correo electronico
   y contrasena**.
2. En **Firestore Database > Crear base de datos**, crea la base en la region
   mas cercana a tus usuarios.
3. En **Storage > Comenzar**, crea el bucket en una region compatible y cercana.
4. Crea/activa **Cloud Functions**; se usaran para validar compras y descubrir
   la melodia en el servidor antes de entregar acceso a audio.
5. Nunca pongas una clave de cuenta de servicio de Firebase en Flutter ni en el
   repositorio.

Firebase puede pedir un plan de facturacion para Storage o Functions. Revisa
precios y limites del proyecto antes de habilitarlos.

## 3. Instalar las herramientas y conectar Flutter

Ejecuta estos comandos desde la carpeta raiz del proyecto, en una terminal que
reconozca `flutter` y `dart`:

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutter pub add firebase_core firebase_auth cloud_firestore firebase_storage cloud_functions
flutterfire configure --project=ID_DEL_PROYECTO --platforms=android,ios,web
```

El Project ID que compartiste es `song-gues-game`; el numero `655179331422` es
el numero del proyecto y `unicesar.edu.co` es un dominio, no se usa como ID en
estos comandos. Confirma en Firebase Console que el ID este escrito exactamente
asi antes de ejecutar. Si no usaras Web, quita `web` de la lista. Para
Android/iOS, ejecuta FlutterFire en Windows; compilar y ejecutar la app iOS
seguira requiriendo macOS con Xcode.

Los comandos para ese proyecto son:

```powershell
flutterfire configure --project=song-gues-game --platforms=android,ios,web
```

`flutterfire configure` genera `lib/firebase_options.dart` y configura los
archivos de plataforma. La app ya inicializa Firebase en Android, iOS y Web.
Supabase sigue inicializandose si se pasan sus variables; no se han migrado
todavia los repositorios ni autenticacion.

La version actual no configura Firebase para Windows, Linux o macOS. Si deseas
probar Firebase en escritorio, vuelve a ejecutar FlutterFire incluyendo esas
plataformas antes de inicializarlo desde ellas.

## 4. Modelo de colecciones propuesto

Firestore no requiere crear tablas ni declarar un esquema antes de usarlas. Una
coleccion aparece en Firebase Console al escribir su primer documento. Estos
son los documentos sugeridos; para poblarlos se puede usar Firebase Console,
un script administrativo privado o Cloud Functions con Admin SDK.

### `users/{uid}`

Documento privado del usuario, con `uid` igual al ID de Firebase Authentication:

```text
email: string
nombre: string
insignias: array<string>
createdAt: timestamp
```

### `users/{uid}/progress/{dificultad}`

Un documento por dificultad (`facil`, `medio`, `avanzado`):

```text
nivelActual: number
nivelesCompletados: array<number>
updatedAt: timestamp
```

### `users/{uid}/difficultyOrders/{dificultad}`

El backend asigna y guarda una permutacion de canciones/niveles distinta para
cada usuario y dificultad. No vuelvas a sortearla al abrir la app:

```text
levelIds: array<string>
createdAt: timestamp
```

Cada elemento de `levelIds` referencia un documento de `levels`. El orden queda
estable para que el progreso no cambie entre sesiones. La coleccion debe
generarse en el servidor, no aceptarse como una lista elegida por el cliente.
La app no debe leer esta subcoleccion directamente; la Edge Function devuelve
solo los niveles de la dificultad actualmente habilitada.

La progresion entre dificultades es secuencial: se empieza en `facil`, y solo
cuando se hayan completado todos los niveles asignados en esa dificultad se
habilita `medio`; al completar todos los de `medio`, se habilita `avanzado`.
El backend debe comprobar ese requisito al iniciar un nivel y al actualizar el
progreso. No basta con ocultar niveles bloqueados en la interfaz.

### `songs/{songId}`

Metadatos de la cancion. El archivo completo se guarda en Storage y solo se
almacena aqui su ruta, nunca el archivo binario ni un enlace permanente:

```text
titulo: string
artista: string
fullAudioPath: string
published: boolean
createdAt: timestamp
```

Ejemplo de `fullAudioPath`: `songs/cancion-001/full/track.mp3`.

### `levels/{levelId}`

Catalogo privado que consulta el backend. La funcion entrega a la app una
version segura del nivel, sin la respuesta:

```text
numero: number
dificultad: "facil" | "medio" | "avanzado"
cancionId: string
puntosInicio: array<number>
published: boolean
instrumentos: map
```

`instrumentos` es un mapa cuyas claves son `caja`, `guacharaca`, `acordeon`,
`piano`, `guitarra`, `bajo` y `trompeta`. Cada valor contiene `precio` (100000,
200000, 300000 o 400000) y `storagePath`. Los precios del nivel suman
2.000.000, igual que la validacion de `Nivel`.

### `levels/{levelId}/fragments/{fragmentId}`

Metadatos de un fragmento sincronizado de cinco segundos:

```text
inicioSegundos: number
duracionSegundos: 5
audioPaths: map<string, string>
```

`audioPaths` contiene la ruta de Storage de cada stem sincronizado. Todos deben
comenzar en el mismo punto de la cancion. Si el proyecto solo tendra un
fragmento por nivel, puede usarse `fragmentId: "fragmento-01"`.

### `privateLevelAnswers/{levelId}`

Documento privado, sin lectura directa desde la app:

```text
instrumentoMelodia: string
respuestaCancionNormalizada: string
```

No incluyas estos campos en `levels/{levelId}`: si el cliente puede leer la
respuesta, el jugador podria descubrirla antes de jugar. Una Cloud Function
debe comparar las compras/respuestas y cambiar el estado de la partida.

### `games/{gameId}` y `games/{gameId}/purchases/{instrumento}`

Estado de una partida por jugador:

```text
uid: string
levelId: string
presupuestoRestante: number
puntoInicio: number
instrumentosComprados: array<string>
melodiaDescubierta: boolean
ganada: boolean
createdAt: timestamp
updatedAt: timestamp
```

La subcoleccion `purchases` puede llevar un documento por instrumento comprado,
con `precio` y `createdAt`. Compra, saldo, descubrimiento y victoria deben
validarse/actualizarse mediante Cloud Functions y transacciones, no con escrituras
del cliente.

## 5. Reglas incluidas en este repositorio

- `firestore.rules`: restringe los datos privados al propietario cuando aplica;
  bloquea la lectura/escritura directa de catálogo, respuestas y órdenes, para
  que el cliente no pueda descubrir respuestas ni alterar el progreso.
- `storage.rules`: bloquea lectura/escritura directa de los audios desde la app.
  El backend debe validar la partida y entregar URLs firmadas de corta duracion
  para reproducir el stem permitido o la cancion completa tras ganar.
- `firebase.json`: conecta las reglas locales con Firebase CLI.

Antes de producción, valida las reglas con Emulator Suite y crea Cloud
Functions para perfil/progreso, partida/compras, validacion de respuestas y
entrega temporal de audio. Las reglas no crean colecciones ni documentos.

Para desplegar las reglas cuando Firebase CLI este instalado y hayas iniciado
sesion:

```powershell
firebase use song-gues-game
firebase deploy --only firestore:rules,storage
```

## 6. Backend de progreso con Supabase Edge Functions

`supabase/functions/game-progress` implementa estas acciones autenticadas:

- `progress`: crea/recupera el orden aleatorio estable por usuario, devuelve el
  progreso y solo los niveles de la dificultad activa.
- `startLevel`: rechaza niveles completados, niveles fuera de orden y niveles
  de dificultades bloqueadas; crea el documento de partida.
- `submitAnswer`: compara la respuesta en el servidor con
  `privateLevelAnswers/{levelId}` y actualiza atómicamente partida y progreso.

La app usa Firebase Authentication para registro e inicio de sesion; el
repositorio `FirebaseGameRepository` llama esta funcion con el ID token de
Firebase. Define `SUPABASE_URL` y `SUPABASE_ANON_KEY` al ejecutar Flutter.
Habilita el proveedor correo/contrasena en Firebase Authentication.

Al ejecutar Flutter, conserva estas variables públicas de Supabase:

```powershell
flutter run --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_PUBLICA
```

Los documentos `levels/{levelId}` se leen desde Firestore y deben tener:

```text
dificultad: "facil" | "medio" | "avanzado"
numero: number
cancionId: string
published: true
instrumentos: map<string, { precio: number, storagePath: string }>
puntosInicio: array<number>
```

Ejemplo de un nivel (en la consola, crea el documento `levels/facil-01`):

```text
dificultad: "facil"
numero: 1
cancionId: "cancion-01"
published: true
puntosInicio: [0, 30]
instrumentos:
  caja:       { precio: 400000, storagePath: "cancion-01/nivel-01/caja.mp3" }
  guacharaca: { precio: 400000, storagePath: "cancion-01/nivel-01/guacharaca.mp3" }
  acordeon:   { precio: 400000, storagePath: "cancion-01/nivel-01/acordeon.mp3" }
  piano:      { precio: 200000, storagePath: "cancion-01/nivel-01/piano.mp3" }
  guitarra:   { precio: 200000, storagePath: "cancion-01/nivel-01/guitarra.mp3" }
  bajo:       { precio: 200000, storagePath: "cancion-01/nivel-01/bajo.mp3" }
  trompeta:   { precio: 200000, storagePath: "cancion-01/nivel-01/trompeta.mp3" }
```

En `privateLevelAnswers/facil-01`, crea `respuestaCancionNormalizada` con el
título verdadero. No agregues ese título ni `instrumentoMelodia` a
`levels/facil-01`. Cuando se completen todos los niveles de Fácil, Media se
desbloquea aunque todavía no tenga canciones publicadas; aparecerá sin niveles
hasta que se agreguen. Lo mismo aplica a Avanzada después de Media. Los niveles
nuevos se agregan al final del orden personal con orden aleatorio, sin alterar
los ya asignados. No elimines ni despubliques niveles ya incluidos en una orden.

Guarda la respuesta verdadera solo en
`privateLevelAnswers/{levelId}.respuestaCancionNormalizada` (o en el campo
`titulo`). Publica primero los niveles y sus respuestas. El servidor asigna y
persiste una permutacion a cada usuario; al completar todos los IDs de una
dificultad, desbloquea la siguiente. Las escrituras usan precondiciones de
Firestore para rechazar actualizaciones concurrentes de partidas/progreso.

La cuenta de servicio usada por la funcion necesita permiso de lectura y
escritura de Firestore, por ejemplo **Cloud Datastore User**. No uses una clave
de cuenta de servicio con permisos de propietario del proyecto.

## 7. Audio privado con Supabase Storage y Firebase

La app puede pedir enlaces temporales a `supabase/functions/audio-link`. La
funcion valida el ID token de Firebase, consulta con permisos de servidor la
partida y el nivel en Firestore, y solo devuelve la URL firmada del objeto que
corresponda. La app no envia rutas de Storage arbitrarias.

Buckets recomendados:

- `instrumentos`: stems/fragmentos por instrumento.
- `canciones-completas`: canciones completas, desbloqueadas tras ganar.

No crees un bucket por cancion. Organiza objetos con rutas como
`cancion-001/nivel-01/guitarra.mp3` y `cancion-001/track.mp3`. Ambos buckets
deben ser **privados**. El bucket existente `instrumentos` aparece como publico
en el dashboard; vuelve privado su ajuste de acceso cuando estes listo para
usar el backend. Mientras siga publico, cualquier persona con su URL podra
evitar esta funcion y los enlaces firmados no protegeran esos archivos.

En los documentos Firestore usados por esta funcion:

- `games/{gameId}` incluye `uid`, `levelId`, `puntoInicio`,
  `instrumentosComprados`, `melodiaDescubierta` y `ganada`.
- `levels/{levelId}` incluye `published`, `cancionId` y `instrumentos`, donde
  cada instrumento puede tener `storagePath`.
- `levels/{levelId}/fragments/{fragmentId}` incluye `inicioSegundos` y
  `audioPaths`, un mapa de instrumento a ruta de Storage.
- `songs/{songId}` incluye `published` y `fullAudioPath`.

La funcion permite un stem comprado; una vez `melodiaDescubierta` es verdadero,
permite cualquier stem del nivel. La cancion completa solo se firma cuando
`ganada` es verdadero. Las escrituras de compras, descubrimiento y victoria
tienen que proceder de un backend confiable: no habilites escrituras del
cliente a esos campos. El backend tambien debe asignar una sola vez el orden
aleatorio de cada dificultad por usuario, conservarlo y rechazar el inicio de
niveles de dificultad media/avanzada si no se ha completado toda la dificultad
anterior.

Antes de desplegar, crea una cuenta de servicio de Google Cloud con permiso de
lectura/escritura a Firestore (por ejemplo, **Cloud Datastore User**) y guarda el
JSON de su clave solo como secreto de Supabase. Configura estos secretos en
**Supabase Dashboard > Edge Functions > Secrets**:

- `FIREBASE_PROJECT_ID`: `song-gues-game`
- `FIREBASE_SERVICE_ACCOUNT_JSON`: contenido completo del JSON de la cuenta de
  servicio
- `SUPABASE_URL`: URL del proyecto Supabase
- `SUPABASE_SERVICE_ROLE_KEY`: clave de servidor de Supabase
- `SUPABASE_STEMS_BUCKET`: `instrumentos`
- `SUPABASE_FULL_SONGS_BUCKET`: `canciones-completas`

No pongas el JSON de la cuenta de servicio ni la clave `service_role` en Flutter,
en Git o en una variable `dart-define`. Limita la cuenta de servicio a lectura
de Firestore; la clave `service_role` solo se usa en la Edge Function para
firmar enlaces de Storage.

Instala/inicia Supabase CLI, enlaza el proyecto y despliega desde la raiz del
repositorio:

```powershell
supabase login
supabase link --project-ref TU_PROJECT_REF
supabase functions deploy game-progress
supabase functions deploy audio-link
```

La configuracion local desactiva la validacion JWT de Supabase para esta
funcion, porque los usuarios se autentican con Firebase. La funcion valida
manualmente cada ID token de Firebase. Prueba primero con archivos de prueba y
una partida cuyos campos hayan sido escritos de manera confiable.

**Alcance actual:** `game-progress` crea partidas, valida respuestas y guarda
el avance secuencial. Todavia no implementa las compras de instrumentos ni la
reproduccion desde la interfaz. La entrega temporal de audio se implementa por
separado en `audio-link`; las compras y el descubrimiento de la melodia deben
añadirse a un flujo de servidor antes de poner los buckets privados.

No retires Supabase ni sus dependencias hasta que autenticacion, catalogo,
partidas, progreso y audio hayan sido probados en Firebase/Supabase.
