import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5.9.6";

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
  "caja",
  "guacharaca",
  "acordeon",
  "piano",
  "guitarra",
  "bajo",
  "trompeta",
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
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function privateKeyBytes(pem: string): Uint8Array {
  const encoded = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
}

async function firestoreToken(): Promise<string> {
  if (cachedServiceToken && cachedServiceToken.expiresAt > Date.now() + 60_000) {
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
    console.error("Firebase service token exchange failed", tokenResponse.status);
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
    console.error("Firestore document read failed", result.status, path);
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
    console.error("Firestore collection read failed", result.status, path);
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
    throw new HttpError(409, "El progreso cambió en otra solicitud; inténtalo de nuevo");
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

function userPath(uid: string, collection: string, difficulty: Difficulty) {
  return `users/${uid}/${collection}/${difficulty}`;
}

async function ensureOrder(
  token: string,
  uid: string,
  difficulty: Difficulty,
): Promise<string[]> {
  const path = userPath(uid, "difficultyOrders", difficulty);
  const existing = await getDocument(token, path);
  const documents = await listCollection(token, "levels");
  const levels = documents.filter((document) => {
    const fields = fromFields(document.fields ?? {});
    return fields.dificultad === difficulty && fields.published === true;
  }).map((document) => document.name?.split("/").at(-1))
    .filter((id): id is string => typeof id === "string");
  if (existing) {
  const rawOrder = existing.fields.levelIds;
  if (
    !Array.isArray(rawOrder) ||
    !rawOrder.every((id) => typeof id === "string")
  ) {
    throw new HttpError(500, "El orden guardado tiene un formato inválido");
  }
  const currentOrder = rawOrder as string[];
  const progress = await getDocument(
    token,
    userPath(uid, "progress", difficulty),
  );
  const completed = new Set(
    Array.isArray(progress?.fields.completedLevelIds)
      ? (progress?.fields.completedLevelIds as unknown[])
        .filter((id): id is string => typeof id === "string")
      : [],
  );
  const difficultyComplete = currentOrder.every((id) => completed.has(id));
  const additions = difficultyComplete
    ? []
    : shuffled(levels.filter((id) => !currentOrder.includes(id)));
  if (additions.length === 0) return currentOrder;
  if (!existing.updateTime) {
    throw new HttpError(500, "No se pudo validar la versión del orden guardado");
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
    return latestIds as string[];
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
    return ids as string[];
  }
}

async function getProgress(
  token: string,
  uid: string,
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
    const order = await ensureOrder(token, uid, difficulty);
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
      userPath(uid, "progress", difficulty),
    );
    const ids = progressDoc?.fields.completedLevelIds;
    const completed = new Set(
      Array.isArray(ids)
        ? ids.filter((id): id is string => typeof id === "string")
        : [],
    );
    const done = order.every((levelId) => completed.has(levelId));
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

  const levelEntries = await Promise.all(
    activeOrder.map(async (id) => {
      const document = await getDocument(token, `levels/${id}`);
      if (!document || document.fields.published !== true) {
        throw new HttpError(409, "Un nivel del orden guardado dejó de estar publicado");
      }
      const fields = document.fields;
      const songId = fields.cancionId;
      if (
        !validId(songId) ||
        !Number.isInteger(fields.numero) ||
        fields.dificultad !== activeDifficulty
      ) {
        throw new HttpError(500, `El nivel ${id} tiene metadatos inválidos`);
      }
      const rawInstruments = fields.instrumentos;
      if (!rawInstruments || typeof rawInstruments !== "object") {
        throw new HttpError(500, `El nivel ${id} no tiene instrumentos`);
      }
      const instrumentEntries = Object.entries(rawInstruments as JsonObject);
      if (instrumentEntries.length !== instrumentTypes.size) {
        throw new HttpError(500, `El nivel ${id} debe tener siete instrumentos`);
      }
      let totalPrice = 0;
      const instruments = instrumentEntries.map(([type, value]) => {
        if (!instrumentTypes.has(type)) {
          throw new HttpError(500, `El instrumento ${type} no es válido`);
        }
          if (!value || typeof value !== "object") {
            throw new HttpError(500, `El instrumento ${type} del nivel no es válido`);
          }
          const instrument = value as JsonObject;
          const price = instrument.precio;
          if (
            typeof price !== "number" ||
            ![100000, 200000, 300000, 400000].includes(price) ||
            typeof instrument.storagePath !== "string"
          ) {
            throw new HttpError(500, `El instrumento ${type} del nivel no está completo`);
          }
          totalPrice += price;
          return {
            tipo: type,
            precio: price,
            audio_url: "",
          };
      });
      if (totalPrice !== 2000000) {
        throw new HttpError(500, `El presupuesto del nivel ${id} debe sumar 2.000.000`);
      }
      const nivel = {
        id,
        numero: fields.numero,
        dificultad: fields.dificultad,
        cancion_id: songId,
        cancion_titulo: "Canción misteriosa",
        instrumentos: instruments,
        puntos_inicio: fields.puntosInicio ?? [],
      };
      return {
        nivel,
        completado: activeCompleted.has(id),
        puede_iniciar: !activeCompleted.has(id) &&
          activeOrder.find((levelId) => !activeCompleted.has(levelId)) === id,
      };
    }),
  );
  return {
    dificultades: summaries,
    dificultad_activa: activeDifficulty,
    niveles: levelEntries,
  };
}

async function startLevel(
  token: string,
  uid: string,
  levelId: string,
): Promise<JsonObject> {
  const state = await getProgress(token, uid);
  const available = (state.niveles as JsonObject[]).find((entry) => {
    const nivel = entry.nivel as JsonObject;
    return nivel.id === levelId;
  });
  if (!available || available.puede_iniciar !== true) {
    throw new HttpError(
      403,
      "Ese nivel está bloqueado o ya fue completado. Continúa con el siguiente nivel habilitado.",
    );
  }

  const random = new Uint32Array(1);
  crypto.getRandomValues(random);
  const gameId = Array.from(crypto.getRandomValues(new Uint8Array(16)))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const nivel = available.nivel as JsonObject;
  const points = nivel.puntos_inicio as number[];
  const startPoint = points.length > 0
    ? points[random[0] % points.length]
    : 0;
  await commitWrites(token, [
    createWrite(`games/${gameId}`, {
      uid,
      levelId,
      dificultad: nivel.dificultad,
      puntoInicio: startPoint,
      presupuestoRestante: 2000000,
      instrumentosComprados: [],
      melodiaDescubierta: false,
      ganada: false,
      failedAnswerAttempts: 0,
      nextAnswerAt: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }),
  ]);
  return { gameId, nivel };
}

async function submitAnswer(
  token: string,
  uid: string,
  gameId: string,
  answer: string,
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
    ensureOrder(token, uid, difficulty as Difficulty),
    getDocument(
      token,
      userPath(uid, "progress", difficulty as Difficulty),
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
    Array.isArray(progress?.fields.completedLevelIds)
      ? (progress?.fields.completedLevelIds as unknown[])
        .filter((id): id is string => typeof id === "string")
      : [],
  );
  const nextLevelId = currentOrder.find((id) => !completedIds.has(id));
  if (nextLevelId !== levelId) {
    throw new HttpError(403, "La partida no corresponde al siguiente nivel activo");
  }
  completedIds.add(levelId);
  const completedNumbers = new Set(
    Array.isArray(progress?.fields.nivelesCompletados)
      ? (progress?.fields.nivelesCompletados as unknown[])
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
  const progressPath = userPath(uid, "progress", difficulty as Difficulty);
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
    progress
      ? updateWrite(progressPath, progressFields, progress.updateTime!)
      : createWrite(progressPath, progressFields),
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
    if (!projectId) throw new HttpError(500, "Falta configurar FIREBASE_PROJECT_ID");
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
    if (action === "progress") {
      return response(200, { estado: await getProgress(token, uid) });
    }
    if (action === "startLevel") {
      if (!validId(body.levelId)) {
        throw new HttpError(400, "levelId no es válido");
      }
      return response(
        200,
        await startLevel(token, uid, body.levelId),
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
        await submitAnswer(token, uid, body.gameId, body.answer),
      );
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
