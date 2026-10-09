import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5.9.6";
import {
  canPurchaseInstrument,
  maxPurchasedInstruments,
  selectMelodyInstrument,
  selectNextInstrumentPrice,
} from "./pricing.ts";
import {
  levelsPerDifficulty,
  selectDifficultyLevels,
} from "./level_selection.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const firebaseJwks = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);
const difficulties = ["facil", "medio", "avanzado"] as const;
type Difficulty = (typeof difficulties)[number];
type JsonObject = Record<string, unknown>;
const instrumentTypes = new Set([
  "bateria",
  "acordeon",
  "bajo",
  "guitarra",
]);

interface FirestoreDocument {
  name?: string;
  updateTime?: string;
  fields?: Record<string, unknown>;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

let cachedServiceToken: { token: string; expiresAt: number } | undefined;

function response(status: number, data: JsonObject): Response {
  return new Response(JSON.stringify(data), { status, headers: corsHeaders });
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new HttpError(500, `Falta configurar ${name}`);
  return value;
}

function fromValue(value: unknown): unknown {
  if (!value || typeof value !== "object") return undefined;
  const field = value as JsonObject;
  if ("stringValue" in field) return field.stringValue;
  if ("booleanValue" in field) return field.booleanValue;
  if ("integerValue" in field) return Number(field.integerValue);
  if ("doubleValue" in field) return Number(field.doubleValue);
  if ("timestampValue" in field) return field.timestampValue;
  if ("nullValue" in field) return null;
  if ("arrayValue" in field) {
    const values = (field.arrayValue as { values?: unknown[] }).values ?? [];
    return values.map(fromValue);
  }
  if ("mapValue" in field) {
    return fromFields(
      (field.mapValue as { fields?: Record<string, unknown> }).fields ?? {},
    );
  }
  return undefined;
}

function fromFields(fields: Record<string, unknown>): JsonObject {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, fromValue(value)]),
  );
}

function normalizeDifficulty(value: unknown): string | undefined {
  return typeof value === "string" ? value.trim() : undefined;
}

function toValue(value: unknown): JsonObject {
  if (value === null) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toValue) } };
  }
  if (typeof value === "object") {
    return { mapValue: { fields: toFields(value as JsonObject) } };
  }
  throw new HttpError(500, "Tipo de dato Firestore no soportado");
}

function toFields(value: JsonObject): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(value).map(([key, field]) => [
      key,
      typeof field === "string" &&
        (key === "createdAt" || key === "updatedAt")
        ? { timestampValue: field }
        : toValue(field),
    ]),
  );
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function privateKeyBytes(pem: string): ArrayBuffer {
  const encoded = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

async function firestoreToken(): Promise<string> {
  if (
    cachedServiceToken && cachedServiceToken.expiresAt > Date.now() + 60_000
  ) {
    return cachedServiceToken.token;
  }
  let account: ServiceAccount;
  try {
    account = JSON.parse(
      requiredEnv("FIREBASE_SERVICE_ACCOUNT_JSON"),
    ) as ServiceAccount;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(500, "La cuenta de servicio no es JSON válido");
  }
  if (
    account.project_id !== projectId || !account.client_email ||
    !account.private_key
  ) {
    throw new HttpError(500, "La cuenta de servicio no coincide con Firebase");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const claims = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: account.client_email,
        scope: "https://www.googleapis.com/auth/datastore",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!tokenResponse.ok) {
    console.error(
      "Firebase service token exchange failed",
      tokenResponse.status,
    );
    throw new HttpError(502, "No se pudo autenticar con Firestore");
  }
  const tokenData = await tokenResponse.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!tokenData.access_token) {
    throw new HttpError(502, "Firebase no devolvió un token de servicio");
  }
  cachedServiceToken = {
    token: tokenData.access_token,
    expiresAt: Date.now() + (tokenData.expires_in ?? 3600) * 1000,
  };
  return tokenData.access_token;
}

function documentName(path: string): string {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return `projects/${
    encodeURIComponent(projectId)
  }/databases/(default)/documents/${encoded}`;
}

function documentUrl(path: string): string {
  return `https://firestore.googleapis.com/v1/${documentName(path)}`;
}

async function getDocument(
  token: string,
  path: string,
): Promise<{ fields: JsonObject; updateTime?: string } | null> {
  const result = await fetch(documentUrl(path), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (result.status === 404) return null;
  if (!result.ok) {
    const details = (await result.text()).slice(0, 2000);
    console.error(
      "Firestore document read failed",
      result.status,
      path,
      details,
    );
    throw new HttpError(502, "No se pudieron consultar los datos del juego");
  }
  const document = await result.json() as FirestoreDocument;
  return {
    fields: fromFields(document.fields ?? {}),
    updateTime: document.updateTime,
  };
}

async function listCollection(
  token: string,
  path: string,
  pageToken?: string,
): Promise<FirestoreDocument[]> {
  const url = new URL(documentUrl(path));
  url.searchParams.set("pageSize", "1000");
  if (pageToken) url.searchParams.set("pageToken", pageToken);
  const result = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!result.ok) {
    const details = (await result.text()).slice(0, 2000);
    console.error(
      "Firestore collection read failed",
      result.status,
      path,
      details,
    );
    throw new HttpError(502, "No se pudieron consultar los niveles");
  }
  const data = await result.json() as {
    documents?: FirestoreDocument[];
    nextPageToken?: string;
  };
  const documents = data.documents ?? [];
  if (data.nextPageToken) {
    documents.push(
      ...await listCollection(token, path, data.nextPageToken),
    );
  }
  return documents;
}

async function commitWrites(
  token: string,
  writes: JsonObject[],
): Promise<void> {
  const result = await fetch(
    `https://firestore.googleapis.com/v1/projects/${
      encodeURIComponent(projectId)
    }/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes }),
    },
  );
  if (result.status === 409 || result.status === 412) {
    throw new HttpError(
      409,
      "El progreso cambió en otra solicitud; inténtalo de nuevo",
    );
  }
  if (!result.ok) {
    const details = await result.text();
    if (
      result.status === 400 &&
      /FAILED_PRECONDITION|ALREADY_EXISTS/.test(details)
    ) {
      throw new HttpError(409, "El documento cambió en otra solicitud");
    }
    console.error("Firestore commit failed", result.status, details);
    throw new HttpError(502, "No se pudo guardar el progreso del juego");
  }
}

async function clearDocuments(
  token: string,
  paths: string[],
): Promise<void> {
  for (let index = 0; index < paths.length; index += 450) {
    await commitWrites(
      token,
      paths.slice(index, index + 450).map((name) => ({ delete: name })),
    );
  }
}

async function clearGuestSession(token: string, uid: string): Promise<void> {
  const collections = [
    "games",
    `guestSessions/${uid}/progress`,
    `guestSessions/${uid}/difficultyOrders`,
  ];
  for (const collection of collections) {
    const documents = await listCollection(token, collection);
    const paths = documents
      .filter((document) =>
        collection === "games" ? document.fields?.uid === uid : true
      )
      .map((document) => document.name)
      .filter((name): name is string => typeof name === "string");
    await clearDocuments(token, paths);
  }
}

function createWrite(path: string, fields: JsonObject): JsonObject {
  return {
    update: { name: documentName(path), fields: toFields(fields) },
    currentDocument: { exists: false },
  };
}

function updateWrite(
  path: string,
  fields: JsonObject,
  updateTime: string,
): JsonObject {
  const fieldPaths = Object.keys(fields);
  return {
    update: { name: documentName(path), fields: toFields(fields) },
    updateMask: { fieldPaths },
    currentDocument: { updateTime },
  };
}

function validId(value: unknown): value is string {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function normalizeAnswer(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function shuffled<T>(items: T[]): T[] {
  const result = [...items];
  for (let index = result.length - 1; index > 0; index--) {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const other = random[0] % (index + 1);
    [result[index], result[other]] = [result[other], result[index]];
  }
  return result;
}

function userPath(
  uid: string,
  collection: string,
  difficulty: Difficulty,
  guest = false,
) {
  const root = guest ? `guestSessions/${uid}` : `users/${uid}`;
  return `${root}/${collection}/${difficulty}`;
}

async function ensureOrder(
  token: string,
  uid: string,
  difficulty: Difficulty,
  guest = false,
): Promise<string[]> {
  const path = userPath(uid, "difficultyOrders", difficulty, guest);
  const existing = await getDocument(token, path);
  const documents = await listCollection(token, "levels");
  const levels = selectDifficultyLevels(
    documents.map((document) => {
      const fields = fromFields(document.fields ?? {});
      return {
        id: document.name?.split("/").at(-1) ?? "",
        numero: typeof fields.numero === "number" ? fields.numero : Number.NaN,
        dificultad: normalizeDifficulty(fields.dificultad) ?? "",
        published: fields.published === true,
      };
    }),
    difficulty,
  ).map((level) => level.id);
  if (existing) {
    const rawOrder = existing.fields.levelIds;
    if (
      !Array.isArray(rawOrder) ||
      !rawOrder.every((id) => typeof id === "string")
    ) {
      throw new HttpError(500, "El orden guardado tiene un formato inválido");
    }
    const availableIds = new Set(levels);
    const currentOrder = [...new Set(rawOrder as string[])].filter((id) =>
      availableIds.has(id)
    );
    const additions = shuffled(
      levels.filter((id) => !currentOrder.includes(id)),
    );
    if (
      additions.length === 0 &&
      currentOrder.length === rawOrder.length
    ) return currentOrder;
    if (!existing.updateTime) {
      throw new HttpError(
        500,
        "No se pudo validar la versión del orden guardado",
      );
    }
    const extendedOrder = [...currentOrder, ...additions];
    try {
      await commitWrites(token, [
        updateWrite(
          path,
          { levelIds: extendedOrder, updatedAt: new Date().toISOString() },
          existing.updateTime,
        ),
      ]);
      return extendedOrder;
    } catch (error) {
      if (!(error instanceof HttpError) || error.status !== 409) throw error;
      const latest = await getDocument(token, path);
      const latestIds = latest?.fields.levelIds;
      if (
        !Array.isArray(latestIds) ||
        !latestIds.every((id) => typeof id === "string")
      ) {
        throw error;
      }
      return (latestIds as string[]).filter((id) => levels.includes(id));
    }
  }
  if (levels.length === 0) {
    return [];
  }

  const levelIds = shuffled(levels);
  try {
    await commitWrites(token, [
      createWrite(path, {
        levelIds,
        createdAt: new Date().toISOString(),
      }),
    ]);
    return levelIds;
  } catch (error) {
    if (!(error instanceof HttpError) || error.status !== 409) throw error;
    const concurrentOrder = await getDocument(token, path);
    const ids = concurrentOrder?.fields.levelIds;
    if (!Array.isArray(ids) || !ids.every((id) => typeof id === "string")) {
      throw error;
    }
    return (ids as string[]).filter((id) => levels.includes(id));
  }
}

async function buildLevelEntry(
  token: string,
  id: string,
  difficulty: Difficulty,
  completed: Set<string>,
  canStart: boolean,
): Promise<JsonObject> {
  const document = await getDocument(token, `levels/${id}`);
  if (!document || document.fields.published !== true) {
    throw new HttpError(
      409,
      "Un nivel del orden guardado dejó de estar publicado",
    );
  }
  const fields = document.fields;
  const songId = fields.cancionId;
  const levelDifficulty = normalizeDifficulty(fields.dificultad);
  if (
    !validId(songId) ||
    !Number.isInteger(fields.numero) ||
    levelDifficulty !== difficulty
  ) {
    throw new HttpError(500, `El nivel ${id} tiene metadatos inválidos`);
  }
  const rawInstruments = fields.instrumentos;
  if (!rawInstruments || typeof rawInstruments !== "object") {
    throw new HttpError(500, `El nivel ${id} no tiene instrumentos`);
  }
  const instrumentEntries = Object.entries(rawInstruments as JsonObject);
  const testMode = fields.modoPrueba === true;
  const expectedInstrumentCount = testMode ? 3 : instrumentTypes.size;
  if (instrumentEntries.length !== expectedInstrumentCount) {
    throw new HttpError(
      500,
      testMode
        ? `El nivel de prueba ${id} debe tener tres instrumentos`
        : `El nivel ${id} debe tener cuatro instrumentos`,
    );
  }
  if (
    !instrumentEntries.some(([type]) => type === "acordeon") ||
    !instrumentEntries.some(([type]) => type === "bateria")
  ) {
    throw new HttpError(
      500,
      `El nivel ${id} debe incluir acordeón y batería`,
    );
  }
  const instruments = instrumentEntries.map(([type, value]) => {
    if (!instrumentTypes.has(type)) {
      throw new HttpError(500, `El instrumento ${type} no es válido`);
    }
    if (!value || typeof value !== "object") {
      throw new HttpError(500, `El instrumento ${type} del nivel no es válido`);
    }
    const instrument = value as JsonObject;
    if (
      typeof instrument.storagePath !== "string" ||
      instrument.storagePath.length === 0
    ) {
      throw new HttpError(
        500,
        `El instrumento ${type} del nivel no tiene audio configurado`,
      );
    }
    return { tipo: type, precio: 0, audio_url: "", comprable: true };
  });
  const durationSeconds = fields.duracionFragmentoSegundos ??
    (testMode ? 20 : 30);
  if (durationSeconds !== (testMode ? 20 : 30)) {
    throw new HttpError(
      500,
      testMode
        ? `El nivel de prueba ${id} debe usar fragmentos de 20 segundos`
        : `El nivel ${id} debe usar fragmentos de 30 segundos`,
    );
  }
  return {
    nivel: {
      id,
      numero: fields.numero,
      dificultad: levelDifficulty,
      cancion_id: songId,
      cancion_titulo: "Canción misteriosa",
      instrumentos: instruments,
      puntos_inicio: fields.puntosInicio ?? [],
      modo_prueba: testMode,
      duracion_fragmento_segundos: durationSeconds,
    },
    completado: completed.has(id),
    puede_iniciar: canStart,
  };
}

async function getProgress(
  token: string,
  uid: string,
  guest = false,
): Promise<JsonObject> {
  const summaries: JsonObject[] = [];
  let activeDifficulty: Difficulty = "facil";
  let previousComplete = true;
  let activeOrder: string[] = [];
  let activeCompleted = new Set<string>();
  let stoppedAt: number | null = null;

  for (let index = 0; index < difficulties.length; index++) {
    const difficulty = difficulties[index];
    const unlocked = previousComplete;
    if (!unlocked) {
      summaries.push({
        dificultad: difficulty,
        desbloqueada: false,
        completados: 0,
        total: 0,
      });
      continue;
    }
    const order = await ensureOrder(token, uid, difficulty, guest);
    if (order.length === 0) {
      summaries.push({
        dificultad: difficulty,
        desbloqueada: true,
        completados: 0,
        total: 0,
      });
      activeDifficulty = difficulty;
      activeOrder = [];
      activeCompleted = new Set();
      stoppedAt = index;
      break;
    }
    const progressDoc = await getDocument(
      token,
      userPath(uid, "progress", difficulty, guest),
    );
    const ids = progressDoc?.fields.completedLevelIds;
    const completed = new Set(
      Array.isArray(ids)
        ? ids.filter((id): id is string => typeof id === "string")
        : [],
    );
    const done = order.length === levelsPerDifficulty &&
      order.every((levelId) => completed.has(levelId));
    summaries.push({
      dificultad: difficulty,
      desbloqueada: true,
      completados: order.filter((id) => completed.has(id)).length,
      total: order.length,
    });
    if (!done) {
      activeDifficulty = difficulty;
      activeOrder = order;
      activeCompleted = completed;
      previousComplete = false;
      stoppedAt = index;
      break;
    }
    previousComplete = true;
    activeDifficulty = difficulty;
    activeOrder = order;
    activeCompleted = completed;
  }
  if (stoppedAt !== null) {
    for (const difficulty of difficulties.slice(stoppedAt + 1)) {
      summaries.push({
        dificultad: difficulty,
        desbloqueada: false,
        completados: 0,
        total: 0,
      });
    }
  }

  const nextActiveId = activeOrder.find((id) => !activeCompleted.has(id));
  const levelEntries = await Promise.all(
    activeOrder.map((id) =>
      buildLevelEntry(
        token,
        id,
        activeDifficulty,
        activeCompleted,
        activeCompleted.has(id) || id === nextActiveId,
      )
    ),
  );
  const activeIndex = difficulties.indexOf(activeDifficulty);
  const replayEntries: JsonObject[] = [];
  for (const difficulty of difficulties.slice(0, activeIndex)) {
    const order = await ensureOrder(token, uid, difficulty, guest);
    const progress = await getDocument(
      token,
      userPath(uid, "progress", difficulty, guest),
    );
    const ids = progress?.fields.completedLevelIds;
    const completed = new Set(
      Array.isArray(ids)
        ? ids.filter((id): id is string => typeof id === "string")
        : [],
    );
    const completedIds = order.filter((id) => completed.has(id));
    replayEntries.push(
      ...await Promise.all(
        completedIds.map((id) =>
          buildLevelEntry(token, id, difficulty, completed, true)
        ),
      ),
    );
  }
  return {
    dificultades: summaries,
    dificultad_activa: activeDifficulty,
    niveles: levelEntries,
    niveles_repetibles: replayEntries,
  };
}

async function createOfflineAudioUrl(
  path: string,
  bucket = Deno.env.get("SUPABASE_STEMS_BUCKET") ?? "instrumentos",
): Promise<string> {
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/+$/, "");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const objectPath = path.split("/").map(encodeURIComponent).join("/");
  const result = await fetch(
    `${supabaseUrl}/storage/v1/object/sign/${
      encodeURIComponent(bucket)
    }/${objectPath}`,
    {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ expiresIn: 604800 }),
    },
  );
  if (!result.ok) {
    const details = (await result.text()).slice(0, 1000);
    console.error("Offline audio URL signing failed", result.status, details);
    throw new HttpError(502, "No se pudo preparar la descarga offline de audio");
  }
  const data = await result.json() as {
    signedURL?: string;
    signedUrl?: string;
  };
  const signedUrl = data.signedURL ?? data.signedUrl;
  if (!signedUrl) {
    throw new HttpError(502, "Storage no devolvió la URL de descarga");
  }
  if (/^https?:\/\//i.test(signedUrl)) return signedUrl;
  const pathWithPrefix = signedUrl.startsWith("/storage/v1/")
    ? signedUrl
    : `/storage/v1${signedUrl.startsWith("/") ? signedUrl : `/${signedUrl}`}`;
  return `${supabaseUrl}${pathWithPrefix}`;
}

async function createOfflineBundle(
  token: string,
  uid: string,
  guest: boolean,
): Promise<JsonObject> {
  const state = await getProgress(token, uid, guest);
  const entries = [
    ...(state.niveles as JsonObject[]),
    ...(state.niveles_repetibles as JsonObject[]),
  ];
  const eligible = [...new Map(
    entries
      .filter((entry) => {
        const nivel = entry.nivel as JsonObject;
        return !guest || nivel.dificultad === "facil";
      })
      .map((entry) => {
        const nivel = entry.nivel as JsonObject;
        return [nivel.id as string, entry] as const;
      }),
  ).values()];

  const levels = await Promise.all(eligible.map(async (entry) => {
    const nivel = entry.nivel as JsonObject;
    const levelId = nivel.id as string;
    const [level, answer] = await Promise.all([
      getDocument(token, `levels/${levelId}`),
      getDocument(token, `privateLevelAnswers/${levelId}`),
    ]);
    if (!level || !answer || answer.fields.respuestaCancionNormalizada === undefined) {
      throw new HttpError(404, `Faltan datos offline para ${levelId}`);
    }
    const instruments = level.fields.instrumentos;
    if (!instruments || typeof instruments !== "object") {
      throw new HttpError(500, `El nivel ${levelId} no tiene instrumentos`);
    }
    const songId = nivel.cancion_id;
    if (typeof songId !== "string" || !validId(songId)) {
      throw new HttpError(500, `El nivel ${levelId} no tiene una canción válida`);
    }
    const song = await getDocument(token, `songs/${songId}`);
    const instrumentalPath = song?.fields.instrumentalAudioPath;
    if (
      !song ||
      song.fields.published !== true ||
      typeof instrumentalPath !== "string" ||
      !instrumentalPath
    ) {
      throw new HttpError(404, `Falta la pista instrumental de ${levelId}`);
    }
    const audioUrls: JsonObject = {};
    for (const [instrument, value] of Object.entries(instruments as JsonObject)) {
      if (!instrumentTypes.has(instrument) || !value || typeof value !== "object") {
        throw new HttpError(500, `Instrumentos inválidos en ${levelId}`);
      }
      const storagePath = (value as JsonObject).storagePath;
      if (typeof storagePath !== "string" || !storagePath) {
        throw new HttpError(500, `Falta la ruta del instrumento ${instrument}`);
      }
      audioUrls[instrument] = await createOfflineAudioUrl(storagePath);
    }
    const instrumentalBucket =
      Deno.env.get("SUPABASE_INSTRUMENTAL_SONGS_BUCKET") ??
        "canciones-instrumentales";
    return {
      entry,
      respuesta: answer.fields.respuestaCancionNormalizada,
      audioUrls,
      instrumentalAudioUrl: await createOfflineAudioUrl(
        instrumentalPath,
        instrumentalBucket,
      ),
    };
  }));
  return { estado: state, levels };
}

async function purchaseInstrument(
  token: string,
  uid: string,
  gameId: string,
  instrumentId: string,
): Promise<JsonObject> {
  if (!instrumentTypes.has(instrumentId)) {
    throw new HttpError(400, "El instrumento no es válido");
  }
  const gamePath = `games/${gameId}`;
  const game = await getDocument(token, gamePath);
  if (!game) throw new HttpError(404, "No se encontró la partida");
  if (game.fields.uid !== uid) {
    throw new HttpError(403, "La partida no pertenece a este usuario");
  }
  if (game.fields.ganada === true) {
    throw new HttpError(409, "La partida ya fue completada");
  }
  const levelId = game.fields.levelId;
  if (typeof levelId !== "string" || !validId(levelId)) {
    throw new HttpError(500, "La partida no tiene un nivel válido");
  }
  const level = await getDocument(token, `levels/${levelId}`);
  if (!level || level.fields.published !== true) {
    throw new HttpError(404, "El nivel no está disponible");
  }
  const rawInstruments = level.fields.instrumentos;
  if (!rawInstruments || typeof rawInstruments !== "object") {
    throw new HttpError(500, "El nivel no tiene instrumentos configurados");
  }
  const instrument = (rawInstruments as JsonObject)[instrumentId];
  if (!instrument || typeof instrument !== "object") {
    throw new HttpError(404, "El instrumento no pertenece a este nivel");
  }
  const storagePath = (instrument as JsonObject).storagePath;
  const rawPrices = game.fields.preciosInstrumentos;
  if (typeof storagePath !== "string" || storagePath.length === 0) {
    throw new HttpError(
      500,
      "El instrumento no tiene un audio válido",
    );
  }
  const purchased = Array.isArray(game.fields.instrumentosComprados)
    ? (game.fields.instrumentosComprados as unknown[])
      .filter((item): item is string => typeof item === "string")
    : [];
  const prices = rawPrices && typeof rawPrices === "object" &&
      !Array.isArray(rawPrices)
    ? Object.fromEntries(
      purchased.map((type) => [type, (rawPrices as JsonObject)[type]]),
    )
    : {};
  const purchasePrice = prices[instrumentId];
  if (purchased.includes(instrumentId)) {
    if (
      typeof purchasePrice !== "number" ||
      ![300000, 400000].includes(purchasePrice)
    ) {
      throw new HttpError(500, "No se encontró el precio de la compra");
    }
    return {
      compraRealizada: false,
      presupuestoRestante: game.fields.presupuestoRestante,
      instrumentosComprados: purchased,
      melodiaDescubierta: game.fields.melodiaDescubierta === true,
      precioInstrumento: purchasePrice,
    };
  }
  if (!canPurchaseInstrument(purchased.length)) {
    throw new HttpError(
      409,
      "Ya compraste el máximo de tres instrumentos para esta partida",
    );
  }
  const balance = game.fields.presupuestoRestante;
  if (typeof balance !== "number" || !Number.isInteger(balance)) {
    throw new HttpError(500, "El presupuesto de la partida no es válido");
  }
  const purchasedPrices = purchased.map((type) => {
    const price = prices[type];
    if (typeof price !== "number" || ![300000, 400000].includes(price)) {
      throw new HttpError(500, "El historial de precios de la partida no es válido");
    }
    return price;
  });
  if (
    balance !== 1000000 -
      purchasedPrices.reduce((total, price) => total + price, 0)
  ) {
    throw new HttpError(409, "El saldo no coincide con las compras registradas");
  }
  let price: number;
  try {
    price = selectNextInstrumentPrice(purchasedPrices);
  } catch (error) {
    console.error("Invalid game purchase history", gameId, error);
    throw new HttpError(500, "No se pudo calcular el precio de la compra");
  }
  if (price > balance) {
    throw new HttpError(409, "No tienes presupuesto suficiente para comprarlo");
  }
  const instrumentsPurchased = [...purchased, instrumentId];
  const updatedPrices = { ...prices, [instrumentId]: price };
  let melodyInstrument = game.fields.instrumentoMelodia;
  if (
    instrumentsPurchased.length === maxPurchasedInstruments &&
    (typeof melodyInstrument !== "string" ||
      !instrumentTypes.has(melodyInstrument))
  ) {
    try {
      melodyInstrument = selectMelodyInstrument(
        Object.keys(rawInstruments as JsonObject),
        instrumentsPurchased,
      );
    } catch (error) {
      console.error("Could not assign game melody", gameId, error);
      throw new HttpError(500, "No se pudo asignar la melodía de la partida");
    }
  }
  const melodyFound = (typeof melodyInstrument === "string" &&
    instrumentsPurchased.includes(melodyInstrument)) ||
    game.fields.melodiaDescubierta === true;
  const now = new Date().toISOString();
  if (!game.updateTime) {
    throw new HttpError(500, "No se pudo validar la versión de la partida");
  }
  await commitWrites(token, [
    updateWrite(
      gamePath,
      {
        presupuestoRestante: balance - price,
        preciosInstrumentos: updatedPrices,
        instrumentosComprados: instrumentsPurchased,
        melodiaDescubierta: melodyFound,
        instrumentoMelodia: melodyInstrument,
        updatedAt: now,
      },
      game.updateTime,
    ),
  ]);
  return {
    compraRealizada: true,
    presupuestoRestante: balance - price,
    instrumentosComprados: instrumentsPurchased,
    melodiaDescubierta: melodyFound,
    precioInstrumento: price,
  };
}

async function startLevel(
  token: string,
  uid: string,
  levelId: string,
  guest = false,
): Promise<JsonObject> {
  const state = await getProgress(token, uid, guest);
  const available = (state.niveles as JsonObject[]).find((entry) => {
    const nivel = entry.nivel as JsonObject;
    return nivel.id === levelId;
  });
  const replay = (state.niveles_repetibles as JsonObject[]).find((entry) => {
    const nivel = entry.nivel as JsonObject;
    return nivel.id === levelId;
  });
  const selected = available ?? replay;
  if (
    !selected ||
    selected.puede_iniciar !== true ||
    (selected.completado !== true && available?.puede_iniciar !== true)
  ) {
    throw new HttpError(
      403,
      "Ese nivel está bloqueado. Completa los niveles anteriores o elige uno ya completado para repetirlo.",
    );
  }

  const random = new Uint32Array(1);
  crypto.getRandomValues(random);
  const gameId = Array.from(crypto.getRandomValues(new Uint8Array(16)))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const nivel = selected.nivel as JsonObject;
  const points = nivel.puntos_inicio as number[];
  const startPoint = points.length > 0 ? points[random[0] % points.length] : 0;
  const instrumentList = nivel.instrumentos as JsonObject[];
  const gameLevel = {
    ...nivel,
    instrumentos: instrumentList.map((instrument) => ({
      tipo: instrument.tipo,
      precio: 0,
      audio_url: "",
      comprable: true,
    })),
  };
  await commitWrites(token, [
    createWrite(`games/${gameId}`, {
      uid,
      levelId,
      dificultad: nivel.dificultad,
      puntoInicio: startPoint,
      presupuestoRestante: 1000000,
      preciosInstrumentos: {},
      instrumentosComprados: [],
      melodiaDescubierta: false,
      instrumentoMelodia: null,
      ganada: false,
      failedAnswerAttempts: 0,
      nextAnswerAt: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }),
  ]);
  return { gameId, nivel: gameLevel };
}

async function submitAnswer(
  token: string,
  uid: string,
  gameId: string,
  answer: string,
  guest = false,
): Promise<JsonObject> {
  const gamePath = `games/${gameId}`;
  const game = await getDocument(token, gamePath);
  if (!game) throw new HttpError(404, "No se encontró la partida");
  if (game.fields.uid !== uid) {
    throw new HttpError(403, "La partida no pertenece a este usuario");
  }
  if (game.fields.ganada === true) return { correct: true };
  const nextAnswerAt = game.fields.nextAnswerAt;
  if (
    typeof nextAnswerAt === "string" &&
    Date.parse(nextAnswerAt) > Date.now()
  ) {
    throw new HttpError(429, "Espera 30 segundos antes de volver a intentarlo");
  }
  const levelId = game.fields.levelId;
  const difficulty = game.fields.dificultad;
  if (
    typeof levelId !== "string" || !validId(levelId) ||
    typeof difficulty !== "string" ||
    !difficulties.includes(difficulty as Difficulty)
  ) {
    throw new HttpError(500, "La partida no tiene datos de nivel válidos");
  }

  const [level, answerDoc, order, progress] = await Promise.all([
    getDocument(token, `levels/${levelId}`),
    getDocument(token, `privateLevelAnswers/${levelId}`),
    ensureOrder(token, uid, difficulty as Difficulty, guest),
    getDocument(
      token,
      userPath(uid, "progress", difficulty as Difficulty, guest),
    ),
  ]);
  if (!level || level.fields.published !== true || !answerDoc) {
    throw new HttpError(404, "El nivel no está disponible");
  }
  const correctAnswer = answerDoc.fields.respuestaCancionNormalizada ??
    answerDoc.fields.titulo;
  if (typeof correctAnswer !== "string") {
    throw new HttpError(500, "El nivel no tiene una respuesta configurada");
  }
  if (normalizeAnswer(answer) !== normalizeAnswer(correctAnswer)) {
    const failedAttempts = typeof game.fields.failedAnswerAttempts === "number"
      ? game.fields.failedAnswerAttempts
      : 0;
    const rateLimited = failedAttempts >= 2;
    const now = new Date().toISOString();
    await commitWrites(token, [
      updateWrite(
        gamePath,
        {
          failedAnswerAttempts: rateLimited ? 0 : failedAttempts + 1,
          nextAnswerAt: rateLimited
            ? new Date(Date.now() + 30_000).toISOString()
            : null,
          updatedAt: now,
        },
        game.updateTime!,
      ),
    ]);
    return { correct: false };
  }

  const currentOrder = order;
  const completedIds = new Set(
    Array.isArray(progress?.fields?.completedLevelIds)
      ? (progress.fields.completedLevelIds as unknown[])
        .filter((id): id is string =>
          typeof id === "string" && order.includes(id)
        )
      : [],
  );
  const nextLevelId = currentOrder.find((id) => !completedIds.has(id));
  const replayingCompletedLevel = completedIds.has(levelId);
  if (!replayingCompletedLevel && nextLevelId !== levelId) {
    throw new HttpError(
      403,
      "La partida no corresponde al siguiente nivel activo",
    );
  }
  completedIds.add(levelId);
  const completedNumbers = new Set(
    Array.isArray(progress?.fields?.nivelesCompletados)
      ? (progress.fields.nivelesCompletados as unknown[])
        .filter((number): number is number => typeof number === "number")
      : [],
  );
  if (typeof level.fields.numero === "number") {
    completedNumbers.add(level.fields.numero);
  }
  const now = new Date().toISOString();
  const progressFields = {
    nivelActual: typeof level.fields.numero === "number"
      ? level.fields.numero + 1
      : completedIds.size + 1,
    nivelesCompletados: [...completedNumbers].sort((a, b) => a - b),
    completedLevelIds: [...completedIds],
    updatedAt: now,
  };
  const progressPath = userPath(
    uid,
    "progress",
    difficulty as Difficulty,
    guest,
  );
  const writes = [
    updateWrite(
      gamePath,
      {
        ganada: true,
        failedAnswerAttempts: 0,
        nextAnswerAt: null,
        updatedAt: now,
      },
      game.updateTime!,
    ),
    ...(replayingCompletedLevel ? [] : [
      progress
        ? updateWrite(progressPath, progressFields, progress.updateTime!)
        : createWrite(progressPath, progressFields),
    ]),
  ];
  await commitWrites(token, writes);
  return {
    correct: true,
    completedDifficulty: currentOrder.every((id) => completedIds.has(id)),
  };
}

async function handle(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return response(405, { error: "Método no permitido" });
  }
  try {
    if (!projectId) {
      throw new HttpError(500, "Falta configurar FIREBASE_PROJECT_ID");
    }
    const bearer = request.headers.get("Authorization")
      ?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!bearer) throw new HttpError(401, "Falta el token de Firebase");
    let verified: Awaited<ReturnType<typeof jwtVerify>>;
    try {
      verified = await jwtVerify(bearer, firebaseJwks, {
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
    const uid = verified.payload.sub;
    if (!uid) throw new HttpError(401, "El token no identifica al usuario");
    const firebaseClaim = verified.payload.firebase;
    const guest = firebaseClaim !== null &&
      typeof firebaseClaim === "object" &&
      (firebaseClaim as JsonObject).sign_in_provider === "anonymous";
    let rawBody: unknown;
    try {
      rawBody = await request.json();
    } catch {
      throw new HttpError(400, "El cuerpo debe ser JSON válido");
    }
    if (!rawBody || typeof rawBody !== "object" || Array.isArray(rawBody)) {
      throw new HttpError(400, "El cuerpo debe ser un objeto JSON");
    }
    const body = rawBody as JsonObject;
    const action = body.action;
    const token = await firestoreToken();
    if (action === "startGuestSession") {
      if (!guest) {
        throw new HttpError(
          403,
          "Solo una sesión de invitado puede iniciarse",
        );
      }
      await clearGuestSession(token, uid);
      return response(200, { started: true });
    }
    if (action === "progress") {
      return response(200, { estado: await getProgress(token, uid, guest) });
    }
    if (action === "offlineBundle") {
      return response(
        200,
        { bundle: await createOfflineBundle(token, uid, guest) },
      );
    }
    if (action === "completeOfflineLevel") {
      if (
        !validId(body.levelId) ||
        typeof body.answer !== "string" ||
        body.answer.trim().length === 0 ||
        body.answer.length > 200
      ) {
        throw new HttpError(400, "levelId o respuesta no son válidos");
      }
      const started = await startLevel(token, uid, body.levelId, guest);
      const gameId = started.gameId;
      if (typeof gameId !== "string") {
        throw new HttpError(500, "No se pudo crear la partida offline");
      }
      const result = await submitAnswer(
        token,
        uid,
        gameId,
        body.answer,
        guest,
      );
      if (result.correct !== true) {
        throw new HttpError(400, "La respuesta offline no coincide");
      }
      return response(200, result);
    }
    if (action === "startLevel") {
      if (!validId(body.levelId)) {
        throw new HttpError(400, "levelId no es válido");
      }
      return response(
        200,
        await startLevel(token, uid, body.levelId, guest),
      );
    }
    if (action === "purchaseInstrument") {
      if (
        !validId(body.gameId) ||
        typeof body.instrument !== "string" ||
        !instrumentTypes.has(body.instrument)
      ) {
        throw new HttpError(400, "gameId o instrumento no son válidos");
      }
      return response(
        200,
        await purchaseInstrument(
          token,
          uid,
          body.gameId,
          body.instrument,
        ),
      );
    }
    if (action === "submitAnswer") {
      if (
        !validId(body.gameId) ||
        typeof body.answer !== "string" ||
        body.answer.trim().length === 0 ||
        body.answer.length > 200
      ) {
        throw new HttpError(400, "gameId o respuesta no son válidos");
      }
      return response(
        200,
        await submitAnswer(token, uid, body.gameId, body.answer, guest),
      );
    }
    if (action === "endGuestSession") {
      if (!guest) {
        throw new HttpError(
          403,
          "Solo una sesión de invitado puede finalizarse",
        );
      }
      await clearGuestSession(token, uid);
      return response(200, { cleared: true });
    }
    throw new HttpError(400, "Acción no válida");
  } catch (error) {
    if (error instanceof HttpError) {
      return response(error.status, { error: error.message });
    }
    console.error("Unexpected game-progress function failure", error);
    return response(500, { error: "Error interno al procesar el progreso" });
  }
}

Deno.serve(handle);
