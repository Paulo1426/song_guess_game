# Logica del juego

Este documento describe el flujo implementado en Song Guess Game: autenticacion,
progresion, partidas, precios, audios y las reglas de publicacion de niveles.

## Resumen de reglas

- Hay tres dificultades, en este orden: Facil, Media y Avanzada.
- Cada dificultad usa hasta cinco niveles publicados, elegidos por menor numero.
  Para completar la dificultad y desbloquear la siguiente deben existir y
  completarse los cinco.
- Un nivel normal tiene cuatro instrumentos: Bateria, Acordeon, Bajo y Guitarra.
- El nivel beta puede tener tres instrumentos y fragmentos de 20 segundos. Los
  niveles normales usan fragmentos de 30 segundos.
- Cada partida empieza con $1.000.000 y los cuatro instrumentos disponibles.
  Se compran tres; sus precios se asignan al comprar y suman exactamente el
  presupuesto: $400.000, $300.000 y $300.000.
- Despues de la tercera compra, la melodia queda en el instrumento no comprado
  el 70% de las veces, y en uno de los tres comprados el 30% restante.
- Si la melodia queda en un instrumento comprado, se descubre al completar las
  tres compras. Si queda en el no comprado, no se revela y el jugador puede
  adivinar usando los tres stems comprados.
- Los stems individuales y la mezcla instrumental sin voz se habilitan al
  descubrir la melodia. La grabacion original con voz se habilita al adivinar
  correctamente.

## Inicio de sesion y progreso

La app admite:

- Correo y contrasena.
- Google.
- Modo invitado, sin progreso persistente.

Las cuentas registradas guardan orden y progreso por usuario en Firestore.
Dentro de una dificultad, el servidor conserva un orden personal de niveles;
completar los niveles de la dificultad activa habilita la siguiente. Los niveles
completados se pueden repetir, pero volver a ganarlos no incrementa el progreso
otra vez.

En modo invitado, el servidor guarda el orden y el progreso temporalmente para
validar la secuencia y permitir avanzar durante la sesion. Se limpian las
partidas, el progreso y los ordenes temporales al comenzar una nueva sesion de
invitado o al cerrar sesion. Si se cierra el proceso abruptamente, la limpieza
se realiza al iniciar la proxima sesion.

## Niveles por dificultad

El servidor consulta `levels` y selecciona los cinco niveles que:

1. Estan publicados (`published: true`).
2. Pertenecen a esa dificultad.
3. Tienen el menor valor de `numero`.

El orden de juego de esos cinco niveles se mezcla para cada usuario. Solo se
puede iniciar el siguiente nivel pendiente; los niveles completados se pueden
repetir. El servidor no desbloquea una dificultad siguiente si la dificultad
actual tiene menos de cinco niveles publicados, aunque todos los disponibles
se hayan completado.

Los niveles publicados con numero superior a los cinco seleccionados no
aparecen en el orden activo y no cuentan para la progresion. Si se completan
los cinco niveles de Facil, se habilita Media; tras completar los cinco de
Media, se habilita Avanzada.

Al actualizar el catalogo en Firestore:

- Publica cinco niveles por dificultad para permitir terminarla.
- En niveles normales configura exactamente los cuatro instrumentos vigentes.
- Elimina `caja`, `piano` y `trompeta` de `levels/{levelId}.instrumentos` y de
  cada `audioPaths` de sus fragmentos; incorpora `bateria` con su stem.
- No guardes precios fijos en el catalogo; el servidor los genera para cada
  partida.
- Para el nivel beta, usa `modoPrueba: true`, exactamente tres de los cuatro
  instrumentos vigentes y `duracionFragmentoSegundos: 20`. Los niveles
  normales usan exactamente cuatro instrumentos y fragmentos de 30 segundos.

## Compra y precios

Al crear una partida, los cuatro instrumentos estan disponibles y el saldo
inicial es $1.000.000. Al seleccionar uno para comprar, el servidor asigna y
devuelve su precio:

- La primera compra cuesta aleatoriamente $300.000 o $400.000.
- Si la primera costo $400.000, la segunda cuesta $300.000.
- Si la primera costo $300.000, la segunda puede costar $300.000 o $400.000.
- La tercera cuesta el saldo restante, por lo que las tres compras suman
  exactamente $1.000.000.

El servidor impide una cuarta compra y persiste las compras, sus precios y el
saldo en la partida. Al repetir el nivel se inicia una partida nueva y se
asignan nuevos precios y una nueva melodia.

Despues de la tercera compra, el servidor asigna la melodia con un sorteo de
diez resultados: siete seleccionan el instrumento no comprado y tres
seleccionan uno de los comprados. Si queda en uno comprado, se descubre y se
desbloquean todos los stems y la mezcla instrumental. Si queda en el no
comprado, no se revela al comprar; el jugador puede adivinar con los stems
adquiridos.

## Descubrimiento de la melodia y respuestas

Tras la tercera compra, el servidor guarda la melodia en el documento privado
de la partida (`games/{gameId}.instrumentoMelodia`). No se envia esa seleccion
a la app.

Cada instrumento comprado reproduce su propio stem. Si la melodia queda en uno
de los comprados, el servidor marca `melodiaDescubierta` al completar la tercera
compra y autoriza escuchar los otros instrumentos. Tambien habilita la mezcla
completa sin voz. Si queda en el instrumento no comprado, el jugador puede
seguir intentando respuestas con los tres stems comprados.

La respuesta correcta se consulta en `privateLevelAnswers/{levelId}`, no en el
documento publico del nivel. El servidor normaliza y compara la respuesta.
Cuando es correcta:

- Marca la partida como ganada.
- Registra la finalizacion en el progreso de una cuenta registrada o en el
  progreso temporal del invitado.
- Autoriza la grabacion original con voz.

## Audio

Los stems deben estar sincronizados con el mismo punto inicial. El servidor usa
el punto de inicio elegido para la partida y busca el fragmento que tenga ese
`inicioSegundos`.

- Niveles normales: escucha de 30 segundos por fragmento.
- Nivel beta: escucha de 20 segundos por fragmento.
- Un instrumento comprado reproduce su stem.
- La opcion de escuchar varios instrumentos mezcla los stems comprados. Tras
  encontrar la melodia, permite mezclar los cuatro stems (o todos los presentes
  en el beta).
- La mezcla instrumental completa procede del bucket de canciones
  instrumentales y solo se habilita al descubrir la melodia.
- La grabacion original con voz procede del bucket de canciones completas y
  solo se habilita despues de una respuesta correcta.

Los audios se descargan a la cache privada del dispositivo al reproducirse por
primera vez. La cache permite volver a reproducir archivos ya descargados, pero
la autenticacion, carga de niveles, compras, validacion de respuestas y primera
obtencion del enlace temporal requieren conexion a internet.

## Datos y responsabilidades

Firestore contiene el catalogo de niveles y canciones, respuestas privadas,
partidas y progreso. Supabase Edge Functions hacen las operaciones confiables:

- `game-progress`: seleccion de niveles, creacion de partidas, precios,
  compras, comprobacion de respuestas y progreso.
- `audio-link`: verifica el propietario y estado de la partida, y emite URL
  temporales para los objetos autorizados de Supabase Storage.

La app no debe leer ni escribir directamente las respuestas, el instrumento
melodico secreto, los precios de una partida sin comprar ni el estado interno
de las partidas. Las reglas de Firestore bloquean ese acceso desde el cliente;
las funciones usan la cuenta de servicio del proyecto para las operaciones
necesarias.

## Despliegue de cambios del servidor

Desde la raiz del proyecto, despues de iniciar sesion y enlazar Supabase:

```powershell
npx supabase functions deploy game-progress --project-ref hwjvwabvuavkexgibzps
npx supabase functions deploy audio-link --project-ref hwjvwabvuavkexgibzps
```

Los cambios de interfaz/modelos requieren volver a ejecutar o compilar la app.
Los cambios de las Edge Functions se activan al desplegarlas; no es necesario
reinstalar la app si su codigo local no cambio.
