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
archivos de plataforma. Revisa el diff antes de aceptar cambios. Luego Firebase
se inicializa con `Firebase.initializeApp(options:
DefaultFirebaseOptions.currentPlatform)`. No cambies aun el arranque de la app
ni borres Supabase: la migracion del código va en una etapa posterior.

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

Catalogo que puede consultar un jugador si el nivel esta publicado:

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

- `firestore.rules`: deja leer a cada usuario solo su perfil/progreso/partidas;
  permite leer canciones y niveles publicados a usuarios autenticados; bloquea
  toda escritura directa desde el cliente y toda lectura de respuestas privadas.
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

No retires Supabase ni sus dependencias hasta que autenticacion, catalogo,
partidas, progreso y audio hayan sido migrados y probados en Firebase.
