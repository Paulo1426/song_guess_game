import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5.9.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const firebaseJwks = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

const instrumentIds = new Set([
  "bateria",
  "acordeon",
  "bajo",
  "guitarra",
]);

type JsonObject = Record<string, unknown>;

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface FirestoreDocument {
  fields?: Record<string, unknown>;
}

let cachedAccessToken: { value: string; expiresAt: number } | undefined;

function jsonResponse(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HttpError(500, `Falta configurar el secreto ${name}`);
  }
  return value;
}

function decodeFirestoreValue(value: unknown): unknown {
  if (!value || typeof value !== "object") return undefined;
  const field = value as Record<string, unknown>;

  if ("stringValue" in field) return field.stringValue;
  if ("booleanValue" in field) return field.booleanValue;
  if ("integerValue" in field) return Number(field.integerValue);
  if ("doubleValue" in field) return Number(field.doubleValue);
  if ("timestampValue" in field) return field.timestampValue;
  if ("nullValue" in field) return null;
  if ("arrayValue" in field) {
    const values = (field.arrayValue as { values?: unknown[] }).values ?? [];
    return values.map(decodeFirestoreValue);
  }
  if ("mapValue" in field) {
    const fields =
      (field.mapValue as { fields?: Record<string, unknown> }).fields ?? {};
    return decodeFirestoreFields(fields);
  }
  return undefined;
}

function decodeFirestoreFields(fields: Record<string, unknown>): JsonObject {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [
      key,
      decodeFirestoreValue(value),
    ]),
  );
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function pemToBytes(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const bytes = Uint8Array.from(
    atob(base64),
    (character) => character.charCodeAt(0),
  );
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

async function createGoogleAccessToken(
  serviceAccount: ServiceAccount,
): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = encodeBase64Url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = encodeBase64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: serviceAccount.client_email,
        scope: "https://www.googleapis.com/auth/datastore",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsignedToken = `${header}.${claims}`;
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      privateKey,
      new TextEncoder().encode(unsignedToken),
    ),
  );
  const assertion = `${unsignedToken}.${encodeBase64Url(signature)}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    console.error(
      "Firebase service-account token request failed",
      response.status,
    );
    throw new HttpError(502, "No se pudo autenticar el servicio con Firebase");
  }

  const result = await response.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!result.access_token) {
    throw new HttpError(502, "Firebase no devolvió un token de servicio");
  }
  cachedAccessToken = {
    value: result.access_token,
    expiresAt: Date.now() + (result.expires_in ?? 3600) * 1000,
  };
  return result.access_token;
}

async function firestoreGet(
  projectId: string,
  accessToken: string,
  documentPath: string,
): Promise<JsonObject> {
  const encodedPath = documentPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${
      encodeURIComponent(projectId)
    }/databases/(default)/documents/${encodedPath}`,
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );

  if (response.status === 404) {
    throw new HttpError(404, "No se encontró el recurso solicitado");
  }
  if (!response.ok) {
    console.error("Firestore read failed", response.status, documentPath);
    throw new HttpError(502, "No se pudieron validar los datos de la partida");
  }

  const document = await response.json() as FirestoreDocument;
  return decodeFirestoreFields(document.fields ?? {});
}

function safeObjectPath(path: unknown): string {
  if (typeof path !== "string" || path.length === 0 || path.length > 1024) {
    throw new HttpError(404, "El audio solicitado no está disponible");
  }
  const segments = path.split("/");
  if (
    path.startsWith("/") ||
    segments.some((segment) =>
      segment.length === 0 || segment === "." || segment === ".."
    )
  ) {
    throw new HttpError(400, "La ruta de audio guardada no es válida");
  }
  return path;
}

async function signedStorageUrl(
  bucket: string,
  objectPath: string,
  expiresIn: number,
): Promise<string> {
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/+$/, "");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const encodedPath = objectPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/sign/${
      encodeURIComponent(bucket)
    }/${encodedPath}`,
    {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ expiresIn }),
    },
  );

  if (!response.ok) {
    const errorBody = (await response.text()).slice(0, 1000);
    console.error("Supabase signed URL request failed", {
      status: response.status,
      bucket,
      objectPath,
      error: errorBody,
    });
    throw new HttpError(502, "No se pudo generar el enlace temporal del audio");
  }

  const result = await response.json() as {
    signedURL?: string;
    signedUrl?: string;
  };
  const signedPath = result.signedURL ?? result.signedUrl;
  if (!signedPath) {
    throw new HttpError(502, "Supabase no devolvió un enlace temporal");
  }
  if (/^https?:\/\//i.test(signedPath)) return signedPath;

  const storagePath = signedPath.startsWith("/storage/v1/")
    ? signedPath
    : `/storage/v1${
      signedPath.startsWith("/") ? signedPath : `/${signedPath}`
    }`;
  return `${supabaseUrl}${storagePath}`;
}

function stringField(object: JsonObject, key: string): string | undefined {
  const value = object[key];
  return typeof value === "string" ? value : undefined;
}

function boolField(object: JsonObject, key: string): boolean {
  return object[key] === true;
}

function validId(value: unknown): value is string {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

async function handleRequest(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Método no permitido" });
  }

  try {
    const projectId = requiredEnv("FIREBASE_PROJECT_ID");
    const authHeader = request.headers.get("Authorization");
    const match = authHeader?.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      throw new HttpError(401, "Falta el token de autenticación de Firebase");
    }

    let verifiedToken: Awaited<ReturnType<typeof jwtVerify>>;
    try {
      verifiedToken = await jwtVerify(match[1], firebaseJwks, {
        audience: projectId,
        issuer: `https://securetoken.google.com/${projectId}`,
      });
    } catch (error) {
      const code = (error as { code?: unknown }).code;
      if (typeof code === "string" && /^ERR_(JWT|JWS)_/.test(code)) {
        throw new HttpError(401, "El token de Firebase no es válido o expiró");
      }
      console.error("Firebase token verification service failed", error);
      throw new HttpError(502, "No se pudo verificar el token de Firebase");
    }
    const uid = verifiedToken.payload.sub;
    if (typeof uid !== "string" || uid.length === 0) {
      throw new HttpError(401, "El token de Firebase no identifica al usuario");
    }

    let rawBody: unknown;
    try {
      rawBody = await request.json();
    } catch {
      throw new HttpError(400, "El cuerpo de la solicitud no es JSON válido");
    }
    if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
      throw new HttpError(
        400,
        "El cuerpo de la solicitud debe ser un objeto JSON",
      );
    }
    const body = rawBody as JsonObject;

    const gameId = body.gameId;
    const type = body.type;
    if (!validId(gameId)) {
      throw new HttpError(400, "gameId no es válido");
    }
    if (type !== "stem" && type !== "instrumentalSong" && type !== "fullSong") {
      throw new HttpError(
        400,
        "type debe ser stem, instrumentalSong o fullSong",
      );
    }

    const serviceAccountRaw = requiredEnv("FIREBASE_SERVICE_ACCOUNT_JSON");
    let serviceAccount: ServiceAccount;
    try {
      const rawAccount: unknown = JSON.parse(serviceAccountRaw);
      if (!rawAccount || typeof rawAccount !== "object") {
        throw new Error("Service account must be a JSON object");
      }
      serviceAccount = rawAccount as ServiceAccount;
    } catch {
      throw new HttpError(
        500,
        "FIREBASE_SERVICE_ACCOUNT_JSON no es JSON válido",
      );
    }
    if (
      serviceAccount.project_id !== projectId ||
      !serviceAccount.client_email ||
      !serviceAccount.private_key
    ) {
      throw new HttpError(500, "La cuenta de servicio de Firebase no coincide");
    }

    const firestoreToken = await createGoogleAccessToken(serviceAccount);
    const game = await firestoreGet(
      projectId,
      firestoreToken,
      `games/${gameId}`,
    );
    if (stringField(game, "uid") !== uid) {
      throw new HttpError(403, "La partida no pertenece a este usuario");
    }

    const levelId = stringField(game, "levelId");
    if (!levelId || !validId(levelId)) {
      throw new HttpError(404, "La partida no tiene un nivel válido");
    }

    let bucket: string;
    let objectPath: string;
    let expiresIn: number;

    if (type === "fullSong" || type === "instrumentalSong") {
      const won = boolField(game, "ganada");
      const melodyFound = boolField(game, "melodiaDescubierta");
      if (type === "fullSong" && !won) {
        throw new HttpError(
          403,
          "La canción original se desbloquea al adivinar correctamente",
        );
      }
      if (type === "instrumentalSong" && !melodyFound) {
        throw new HttpError(
          403,
          "La versión instrumental se desbloquea al descubrir la melodía",
        );
      }
      const level = await firestoreGet(
        projectId,
        firestoreToken,
        `levels/${levelId}`,
      );
      if (!boolField(level, "published")) {
        throw new HttpError(404, "El nivel no está publicado");
      }
      const songId = stringField(level, "cancionId");
      if (!songId || !validId(songId)) {
        throw new HttpError(404, "El nivel no tiene una canción válida");
      }
      const song = await firestoreGet(
        projectId,
        firestoreToken,
        `songs/${songId}`,
      );
      if (!boolField(song, "published")) {
        throw new HttpError(404, "La canción no está publicada");
      }
      if (type === "instrumentalSong") {
        bucket = Deno.env.get("SUPABASE_INSTRUMENTAL_SONGS_BUCKET") ??
          "canciones-instrumentales";
        objectPath = safeObjectPath(song.instrumentalAudioPath);
      } else {
        bucket = Deno.env.get("SUPABASE_FULL_SONGS_BUCKET") ??
          "canciones-completas";
        objectPath = safeObjectPath(song.fullAudioPath);
      }
      expiresIn = 1800;
    } else {
      const instrument = body.instrument;
      if (typeof instrument !== "string" || !instrumentIds.has(instrument)) {
        throw new HttpError(400, "El instrumento no es válido");
      }
      const purchased = Array.isArray(game.instrumentosComprados) &&
        game.instrumentosComprados.includes(instrument);
      if (!purchased && !boolField(game, "melodiaDescubierta")) {
        throw new HttpError(403, "Este instrumento aún no está desbloqueado");
      }

      const level = await firestoreGet(
        projectId,
        firestoreToken,
        `levels/${levelId}`,
      );
      if (!boolField(level, "published")) {
        throw new HttpError(404, "El nivel no está publicado");
      }

      const point = game.puntoInicio;
      const fragmentsResponse = await fetch(
        `https://firestore.googleapis.com/v1/projects/${
          encodeURIComponent(projectId)
        }/databases/(default)/documents/levels/${
          encodeURIComponent(levelId)
        }/fragments?pageSize=100`,
        { headers: { Authorization: `Bearer ${firestoreToken}` } },
      );
      if (!fragmentsResponse.ok && fragmentsResponse.status !== 404) {
        console.error(
          "Firestore fragment listing failed",
          fragmentsResponse.status,
        );
        throw new HttpError(502, "No se pudo localizar el fragmento del nivel");
      }
      const fragmentsData = fragmentsResponse.ok
        ? await fragmentsResponse.json() as {
          documents?: FirestoreDocument[];
        }
        : {};
      const fragments = (fragmentsData.documents ?? []).map((document) =>
        decodeFirestoreFields(document.fields ?? {})
      );
      const fragment = fragments.find((item) => item.inicioSegundos === point);
      const audioPaths = fragment?.audioPaths;
      const pathFromFragment = audioPaths &&
          typeof audioPaths === "object" &&
          !Array.isArray(audioPaths)
        ? (audioPaths as JsonObject)[instrument]
        : undefined;
      const instruments = level.instrumentos;
      const instrumentData = instruments &&
          typeof instruments === "object" &&
          !Array.isArray(instruments)
        ? (instruments as JsonObject)[instrument]
        : undefined;
      const pathFromLevel = instrumentData &&
          typeof instrumentData === "object" &&
          !Array.isArray(instrumentData)
        ? (instrumentData as JsonObject).storagePath
        : undefined;
      objectPath = safeObjectPath(pathFromFragment ?? pathFromLevel);
      bucket = Deno.env.get("SUPABASE_STEMS_BUCKET") ?? "instrumentos";
      expiresIn = 600;
    }

    const url = await signedStorageUrl(bucket, objectPath, expiresIn);
    return jsonResponse(200, { url, expiresIn });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(error.status, { error: error.message });
    }
    console.error("Unexpected audio-link function failure", error);
    return jsonResponse(500, { error: "Error interno al autorizar el audio" });
  }
}

Deno.serve(handleRequest);
