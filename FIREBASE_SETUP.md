# Configuracion inicial de Firebase

Esta guia prepara Firebase junto al estado actual de Song Guess Game. La app
todavia usa Supabase; estos pasos configuran Firebase en paralelo, no migran ni
eliminan datos de Supabase.

## 1. Identificadores de las aplicaciones

El repositorio ya tiene estos identificadores:

- Android: `com.example.song_guess_game`
- iOS: `com.example.songGuessGame`

Si quieres publicar la app con otro identificador, cambialo primero en el
proyecto Flutter y usa el mismo valor al registrar la app en Firebase. El ID de
Firebase de una app registrada no se puede renombrar luego.

En Firebase Console, abre **Configuracion del proyecto > Tus aplicaciones** y
registra Android e iOS con esos IDs. Firebase Web no se configura ni se usa en
este proyecto.

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
flutterfire configure --project=ID_DEL_PROYECTO --platforms=android,ios
```

El Project ID que compartiste es `song-gues-game`; el numero `655179331422` es
el numero del proyecto y `unicesar.edu.co` es un dominio, no se usa como ID en
estos comandos. Confirma en Firebase Console que el ID este escrito exactamente
asi antes de ejecutar. Para Android/iOS, ejecuta FlutterFire en Windows;
compilar y ejecutar la app iOS seguira requiriendo macOS con Xcode.

Los comandos para ese proyecto son:

```powershell
flutterfire configure --project=song-gues-game --platforms=android,ios
```

`flutterfire configure` genera `lib/firebase_options.dart` y configura los
archivos de plataforma. Firebase se inicializa solo en Android e iOS. La carpeta
Flutter Web puede seguir en el proyecto, pero la app muestra un aviso de que
Firebase no esta configurado para esa plataforma. Supabase sigue
inicializandose si se pasan sus variables; no se han migrado todavia los
repositorios ni autenticacion.

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

Metadatos de la cancion. Las dos mezclas se guardan en buckets privados de
Storage y aqui solo se almacenan sus rutas, nunca los archivos binarios ni
enlaces permanentes:

```text
titulo: string
artista: string
instrumentalAudioPath: string
fullAudioPath: string
published: boolean
createdAt: timestamp
```

`instrumentalAudioPath` apunta a la mezcla instrumental sin voz y
`fullAudioPath` a la grabacion original con voz. Por ejemplo:
`cancion-001/track.mp3`.

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

`instrumentos` es un mapa con exactamente cuatro claves: `bateria`, `acordeon`,
`bajo` y `guitarra`. Cada valor contiene `storagePath`. No configures precios
permanentes en el catalogo: los cuatro instrumentos empiezan disponibles. En
cada compra, el servidor asigna $300.000 o $400.000 siguiendo el saldo restante;
el precio de la tercera compra completa exactamente el presupuesto de
$1.000.000. Se permiten tres compras y no se predesigna un instrumento fuera de
compra. Los importes de compras anteriores quedan guardados en la partida.

Al actualizar documentos existentes, conserva unicamente las claves
`bateria`, `acordeon`, `bajo` y `guitarra` en `levels/{levelId}.instrumentos`
y en cada mapa `audioPaths` de sus fragmentos. Reemplaza el stem de `caja` por
el de `bateria`; el campo `precio` antiguo puede eliminarse, ya que el servidor
no lo consulta.

Despues de la tercera compra, el servidor asigna la melodia con probabilidad
del 70% al unico instrumento no comprado y con probabilidad del 30% a uno de
los tres comprados. Si queda en un instrumento comprado, se descubre al
completar las tres compras y se desbloquean los cuatro stems y la mezcla
instrumental. Si queda en el instrumento no comprado, no se revela por compra;
el jugador puede adivinar la cancion usando los tres instrumentos comprados.

Si publicas un nivel beta de tres instrumentos, incluye siempre `acordeon` y
`bateria`; el tercer instrumento puede ser `bajo` o `guitarra`.

Cada dificultad utiliza solo los cinco niveles publicados con menor `numero`.
Los niveles con numero superior quedan fuera del orden y del progreso activo;
los anteriores a esta regla no cuentan para desbloquear la siguiente dificultad.
Publica cinco niveles en Fácil, cinco en Media y cinco en Avanzada. Si hay menos
de cinco publicados en la dificultad actual, los publicados se pueden jugar,
pero la dificultad no se considera completa hasta tener y superar los cinco.

### `levels/{levelId}/fragments/{fragmentId}`

Metadatos opcionales de un fragmento sincronizado cuando un nivel tiene varios
puntos de inicio. Los fragmentos normales duran 30 segundos; los niveles
marcados como prueba pueden usar veinte:

```text
inicioSegundos: number
duracionSegundos: 20 | 30
audioPaths: map<string, string>
```

`audioPaths` contiene la ruta de Storage de cada stem sincronizado. Todos deben
comenzar en el mismo punto de la cancion. Si cada nivel tiene un solo fragmento
de 30 segundos, guarda `duracionFragmentoSegundos: 30`, `puntosInicio: [0]` y
las rutas directamente en `levels/{levelId}.instrumentos`; no necesitas crear
esta subcoleccion.

### Nivel de prueba con tres instrumentos

Para probar los tres stems ya subidos sin cambiar las reglas de niveles
normales, marca solo el nivel de prueba con `modoPrueba: true` y
`duracionFragmentoSegundos: 20`. En este modo se aceptan tres instrumentos y se
aplican las mismas reglas de precio. Si se usa este modo, los tres instrumentos
cuestan 400000, 300000 y 300000 y todos son comprables. El presupuesto es
1000000. No dejes `modoPrueba` activado en los niveles de la APP.

Con los archivos de ejemplo `bateria.mp3`, `bajo.mp3` y `acordeon.mp3`, crea o
actualiza estos documentos:

- `songs/cancion-001`: `published: true` y
  `instrumentalAudioPath: "cancion-001/por_supuesto_que_no_instrumental.mp3"`
  (en el bucket `canciones-instrumentales`) y
  `fullAudioPath: "cancion-001/por_supuesto_que_no.mp3"` (en el bucket
  `canciones-completas`).
- `levels/facil-01`: `numero: 1`, `dificultad: "facil"`,
  `cancionId: "cancion-001"`, `published: true`, `modoPrueba: true`,
  `duracionFragmentoSegundos: 20`, `puntosInicio: [0]` e `instrumentos`:

```text
instrumentos:
  acordeon:
    storagePath: "cancion-001/nivel-01/fragmento-00/acordeon.mp3"
  bajo:
    storagePath: "cancion-001/nivel-01/fragmento-00/bajo.mp3"
  bateria:
    storagePath: "cancion-001/nivel-01/fragmento-00/bateria.mp3"
```

- `levels/facil-01/fragments/fragmento-00`: `inicioSegundos: 0`,
  `duracionSegundos: 20` y `audioPaths` con las mismas tres claves y rutas
  anteriores. Los archivos deben estar en el bucket privado `instrumentos`.
- `privateLevelAnswers/facil-01`:
  `respuestaCancionNormalizada: "por supuesto que no"`.

No agregues `modoPrueba` a los otros niveles. El servidor solo devuelve las
rutas después de una compra válida; al descubrir la melodía autoriza los otros
stems y la mezcla instrumental completa. La grabacion original se autoriza
unicamente al responder correctamente.

### Publicar cinco niveles normales de Fácil

Para cargar las cinco canciones ya preparadas, crea o actualiza `songs` y
`levels` con pares como `cancion-001` / `facil-01` hasta `cancion-005` /
`facil-05`. En cada documento `songs/{songId}`, guarda los paths de sus dos
mezclas. En cada `levels/{levelId}`, configura `numero` de 1 a 5,
`dificultad: "facil"`, el `cancionId` correspondiente, `published: true`,
`modoPrueba: false`, `duracionFragmentoSegundos: 30`, `puntosInicio: [0]` y
los cuatro instrumentos. Ejemplo para un nivel con la estructura de Storage
`instrumentos/cancion-001/nivel-01/`:

```text
instrumentos:
  acordeon:
    storagePath: "cancion-001/nivel-01/acordeon.mp3"
  bajo:
    storagePath: "cancion-001/nivel-01/bajo.mp3"
  bateria:
    storagePath: "cancion-001/nivel-01/bateria.mp3"
  guitarra:
    storagePath: "cancion-001/nivel-01/guitarra.mp3"
```

Cada archivo debe contener el mismo fragmento sincronizado de 30 segundos.
Puedes guardar esos stems directamente dentro de la carpeta `nivel-XX`; con un
solo fragmento no hace falta una subcarpeta `fragmento-00` ni crear documentos
en `fragments`. Verifica que el uso de mayúsculas coincida exactamente: por
ejemplo, `guitarra.MP3` y `guitarra.mp3` son rutas distintas.

Para cargar niveles usa `scripts/cargar_niveles_firestore.mjs` con un JSON de
cinco niveles. El script acepta `niveles-facil.json`, `niveles-media.json` y
`niveles-dificil.json`, valida que sus IDs y canciones correspondan a la
dificultad y genera las rutas de los cuatro stems con el patrón
`{songId}/nivel-{numero}/`. Completa para cada canción el título, artista,
respuesta y las rutas exactas de las dos mezclas. Usa los nombres completos que
aparecen en Supabase; las rutas distinguen mayúsculas, minúsculas y guiones bajos.
El script normaliza las respuestas antes de guardarlas.

La estructura esperada en Supabase es:

```text
canciones-completas/{songId}/{archivo-original}.mp3
canciones-instrumentales/{songId}/{archivo-instrumental}.mp3
instrumentos/{songId}/nivel-{numero}/acordeon.mp3
instrumentos/{songId}/nivel-{numero}/bajo.mp3
instrumentos/{songId}/nivel-{numero}/bateria.mp3
instrumentos/{songId}/nivel-{numero}/guitarra.mp3
```

Por ejemplo, para `cancion-004` el nivel Fácil 4 usa la carpeta
`instrumentos/cancion-004/nivel-04/`. No agregues `fragmento-00`: estos niveles
usan un único fragmento sincronizado de 30 segundos desde el segundo 0. Verifica
que las cuatro pistas de cada canción correspondan a la misma canción y al mismo
fragmento.

El script primero hace una vista previa y no escribe nada. Para autorizar la
carga, ejecuta con `--apply` y el JSON deseado. Por ejemplo:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\ruta-segura\firebase-service-account.json"
node scripts\cargar_niveles_firestore.mjs .\niveles-media.json
node scripts\cargar_niveles_firestore.mjs .\niveles-media.json --apply
```

Para Fácil o Avanzada, reemplaza el nombre del archivo por
`niveles-facil.json` o `niveles-dificil.json`. Usa una cuenta de servicio local del proyecto
`song-gues-game` con permiso de escritura en Firestore; guarda el archivo de
credenciales fuera del repositorio y define `GOOGLE_APPLICATION_CREDENTIALS`
con su ruta. Nunca subas ni compartas ese archivo. El JSON real
`niveles-facil.json` y las respuestas no deben subirse al repositorio.
La carga actualiza solo los campos indicados de `songs`, `levels` y
`privateLevelAnswers`; no borra otros campos ni subcolecciones existentes.
Los archivos de audio deben estar ya subidos a los buckets de Supabase: este
script solo registra sus rutas en Firestore.

En PowerShell, desde la raíz del repositorio:

```powershell
Copy-Item scripts\niveles-facil.example.json scripts\niveles-facil.json
# Edita scripts\niveles-facil.json y reemplaza todos los valores de ejemplo.
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\ruta-segura\firebase-service-account.json"
node scripts\cargar_niveles_firestore.mjs
node scripts\cargar_niveles_firestore.mjs --apply
```

Revisa que la vista previa muestre las cinco canciones y las rutas correctas
antes de ejecutar `--apply`.

### Probar en un teléfono Android físico

La lógica del juego y de los cuatro instrumentos es la misma en un teléfono y
en un emulador; la aplicación llama a las mismas funciones de Supabase y usa
los mismos documentos de Firestore. Lo que sí cambia es la conexión y la
instalación. Activa las Opciones de desarrollador y la Depuración por USB en el
teléfono, conéctalo al PC y acepta el diálogo de autorización. Desde la raíz del
proyecto:

```powershell
flutter devices
flutter run -d ID_DEL_TELEFONO `
  --dart-define=SUPABASE_URL=https://hwjvwabvuavkexgibzps.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=TU_CLAVE_ANON_PUBLICA
```

Reemplaza `ID_DEL_TELEFONO` por el identificador que muestre `flutter devices`.
La clave anon es la clave pública (`anon`/`publishable`) de Supabase; no uses ni
compartas la clave `service_role` en la aplicación. Para instalar un APK de
prueba manualmente, también puedes compilarlo con esos mismos `--dart-define` y
abrir `build\app\outputs\flutter-apk\app-debug.apk` en el teléfono. No se puede
compilar una app iOS desde Windows.

### `privateLevelAnswers/{levelId}`

Documento privado, sin lectura directa desde la app:

```text
respuestaCancionNormalizada: string
```

Despues de la tercera compra, el servidor elige y guarda la asignacion en
`games/{gameId}.instrumentoMelodia`, siguiendo la probabilidad 70/30 descrita
en la regla de niveles.
Configura `instrumentalAudioPath` en el documento `songs/{songId}` para la
version sin voz.

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
preciosInstrumentos: map<string, number>
instrumentosComprados: array<string>
melodiaDescubierta: boolean
ganada: boolean
createdAt: timestamp
updatedAt: timestamp
```

La subcoleccion `purchases` puede llevar un documento por instrumento comprado,
con `precio` y `createdAt`. Compra, saldo, descubrimiento y victoria deben
validarse/actualizarse mediante Cloud Functions y transacciones, no con escrituras
del cliente. `preciosInstrumentos` empieza vacio y va guardando el precio de
cada instrumento al comprarlo; no asignes precios a instrumentos no comprados.

## 5. Reglas incluidas en este repositorio

- `firestore.rules`: restringe los datos privados al propietario cuando aplica;
  bloquea la lectura/escritura directa de catálogo, respuestas y órdenes, para
  que el cliente no pueda descubrir respuestas ni alterar el progreso.
- `storage.rules`: bloquea lectura/escritura directa de los audios desde la app.
  El backend debe validar la partida y entregar URLs firmadas de corta duracion
  para stems permitidos, mezcla instrumental al descubrir la melodia y grabacion
  original tras ganar.
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
  progreso, los niveles de la dificultad activa y los niveles completados que
  se pueden repetir en dificultades ya desbloqueadas.
- `startLevel`: rechaza niveles fuera de orden y niveles de dificultades
  bloqueadas, pero permite repetir los completados; crea la partida sin alterar
  el progreso ya ganado.
- `purchaseInstrument`: valida el instrumento y el presupuesto en el servidor,
  registra la compra y comprueba si contiene la melodia.
- `submitAnswer`: compara la respuesta en el servidor con
  `privateLevelAnswers/{levelId}` y actualiza atómicamente partida y progreso.

`supabase/functions/audio-link` valida la partida y entrega URLs firmadas:
permite stems comprados, todos los stems despues de descubrir la melodia y la
mezcla instrumental completa al descubrirla. La grabacion original se autoriza
solo tras ganar.

En la pantalla de juego, cada botón de instrumento reproduce solamente su stem.
“Escuchar instrumentos comprados” mezcla en sincronía los stems adquiridos, y
al descubrir la melodía “Escuchar todos los instrumentos” mezcla todos los
stems del fragmento (20 segundos en modo de prueba). La canción instrumental
completa se reproduce por separado.

La app usa Firebase Authentication para registro e inicio de sesion; el
repositorio `FirebaseGameRepository` llama esta funcion con el ID token de
Firebase. Define `SUPABASE_URL` y `SUPABASE_ANON_KEY` al ejecutar Flutter.
Habilita los proveedores **Correo/Contraseña**, **Google** y **Anonimo** en
Firebase Authentication. Las cuentas anonimas pueden avanzar y completar
niveles durante la sesion; el orden y el progreso temporal se guardan en
`guestSessions/{uid}` para poder validar la progresion del lado del servidor.
Al iniciar de nuevo la app, la sesion temporal anterior se limpia y comienza
desde cero. Tambien se limpia al cerrar sesion de invitado. El progreso de
cuentas registradas se guarda normalmente en `users/{uid}`.

Para habilitar Google Sign-In en Android:

1. En Firebase Console, abre **Configuracion del proyecto > Tus aplicaciones** y
   confirma el paquete `com.example.song_guess_game`.
2. En `android`, ejecuta `.\gradlew signingReport` y copia el SHA-1 del bloque
   `debug`.
3. Agrega ese SHA-1 a la aplicacion Android en Configuracion del proyecto.
4. En **Authentication > Proveedores**, habilita Google.
5. Descarga el nuevo `google-services.json` y reemplaza
   `android/app/google-services.json`. Debe incluir un cliente OAuth web.

Los audios se descargan a la cache privada del dispositivo al escucharlos por
primera vez. Se pueden reutilizar sin red mientras el archivo siga en cache,
pero iniciar sesion, cargar niveles, comprar, validar respuestas y obtener por
primera vez un enlace de audio requieren internet.

Si los registros de `game-progress` muestran `Firestore ... failed 403`, confirma
que la API de Cloud Firestore este habilitada en el proyecto Firebase y que la
cuenta de servicio del secreto `FIREBASE_SERVICE_ACCOUNT_JSON` tenga el rol
`Cloud Datastore User` (`roles/datastore.user`) en ese mismo proyecto. El campo
`client_email` del JSON debe coincidir con la cuenta a la que se otorgo el rol.

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
instrumentos: map<string, { storagePath: string }>
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
  bateria:  { storagePath: "cancion-01/nivel-01/bateria.mp3" }
  acordeon:  { storagePath: "cancion-01/nivel-01/acordeon.mp3" }
  bajo:      { storagePath: "cancion-01/nivel-01/bajo.mp3" }
  guitarra:  { storagePath: "cancion-01/nivel-01/guitarra.mp3" }
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
- `canciones-instrumentales`: mezcla completa sin voz, desbloqueada al encontrar
  el instrumento melódico.
- `canciones-completas`: grabación original con voz, desbloqueada al adivinar
  correctamente la canción.

No crees un bucket por cancion. Organiza objetos con rutas como
`cancion-001/nivel-01/guitarra.mp3` y `cancion-001/track.mp3`. Todos los buckets
deben ser **privados**. El bucket existente `instrumentos` aparece como publico
en el dashboard; vuelve privado su ajuste de acceso cuando estes listo para
usar el backend. Mientras siga publico, cualquier persona con su URL podra
evitar esta funcion y los enlaces firmados no protegeran esos archivos.

En los documentos Firestore usados por esta funcion:

- `games/{gameId}` incluye `uid`, `levelId`, `puntoInicio`,
  `preciosInstrumentos`, `instrumentosComprados`, `instrumentoMelodia`
  (seleccionado al azar entre los tres comprables), `melodiaDescubierta` y
  `ganada`. Los precios privados son una asignacion aleatoria de
  `400000, 300000, 300000, 0`; no la devuelvas a la app.
- `levels/{levelId}` incluye `published`, `cancionId` y `instrumentos`, donde
  cada instrumento puede tener `storagePath`.
- `levels/{levelId}/fragments/{fragmentId}` incluye `inicioSegundos` y
  `audioPaths`, un mapa de instrumento a ruta de Storage.
- `songs/{songId}` incluye `published`, `instrumentalAudioPath` y
  `fullAudioPath`.

La funcion permite un stem comprado; una vez `melodiaDescubierta` es verdadero,
permite cualquier stem y la mezcla instrumental completa. La grabacion original
solo se firma cuando `ganada` es verdadero. Las escrituras de compras,
descubrimiento y victoria tienen que proceder de un backend confiable: no
habilites escrituras del cliente a esos campos. El backend tambien debe asignar
una sola vez el orden aleatorio de cada dificultad por usuario, conservarlo y
rechazar el inicio de niveles de dificultad media/avanzada si no se ha
completado toda la dificultad anterior.

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
- `SUPABASE_INSTRUMENTAL_SONGS_BUCKET`: `canciones-instrumentales`
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
