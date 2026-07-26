import { AwsClient } from "aws4fetch";

export interface Env {
  DB: D1Database;
  VIDEOS: R2Bucket;
  PUBLIC_RATE_LIMITER?: RateLimit;
  APP_API_TOKEN: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  PROFESSIONAL_SIGNATURE: string;
  CLOUDFLARE_ACCOUNT_ID: string;
  R2_BUCKET_NAME: string;
  PUBLIC_BASE_URL: string;
  MAX_VIDEO_SIZE_BYTES: string;
  VIDEO_RETENTION_DAYS: string;
  ANALYTICS_RETENTION_DAYS: string;
}

type VideoStatus =
  | "pending" | "uploading" | "available" | "failed"
  | "revoked" | "expired" | "deleted";

interface VideoRow {
  id: string;
  short_code: string;
  object_key: string;
  idempotency_key: string;
  content_type: string;
  size_bytes: number;
  duration_seconds: number | null;
  status: VideoStatus;
  created_at: string;
  uploaded_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
  sha256: string;
  etag: string | null;
  upload_attempts: number;
}

interface CreateVideoBody {
  idempotency_key: string;
  content_type: string;
  size_bytes: number;
  duration_seconds?: number;
  sha256: string;
}

type AnalyticsEvent = "page_view" | "play_start" | "play_complete";
type DeviceClass = "mobile" | "tablet" | "desktop";

const jsonHeaders = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
  "X-Content-Type-Options": "nosniff",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
};

const pageHeaders = {
  "Cache-Control": "private, no-store",
  "Content-Type": "text/html; charset=utf-8",
  "Content-Security-Policy":
    "default-src 'none'; media-src 'self'; style-src 'unsafe-inline'; " +
    "script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; " +
    "form-action 'none'",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow, noarchive",
};

export function formatShortCode(code: string): string {
  return `${code.slice(0, 3)}-${code.slice(3)}`;
}

export function normalizeShortCode(value: string): string | null {
  const normalized = value.replace("-", "");
  return /^[1-9][0-9]{5}$/.test(normalized) ? normalized : null;
}

export function parseRecentStatsLimit(value: string | null): number | null {
  if (value === null) return 20;
  if (!/^[1-9][0-9]*$/.test(value)) return null;
  const limit = Number(value);
  return Number.isSafeInteger(limit) && limit <= 100 ? limit : null;
}

export function generateShortCode(random = crypto.getRandomValues(
  new Uint32Array(1),
)[0]): string {
  // Rejection sampling is performed by the caller when the small modulo tail occurs.
  return String(100000 + (random % 900000));
}

function randomCode(): string {
  const range = 900000;
  const limit = Math.floor(0x1_0000_0000 / range) * range;
  while (true) {
    const value = crypto.getRandomValues(new Uint32Array(1))[0];
    if (value < limit) return String(100000 + (value % range));
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: jsonHeaders });
}

function log(event: string, fields: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ event, ...fields }));
}

export function classifyDevice(userAgent: string, mobileHint = ""): DeviceClass {
  const normalized = userAgent.toLowerCase();
  if (
    /ipad|tablet|kindle|silk|playbook/.test(normalized) ||
    (/android/.test(normalized) && !/mobile/.test(normalized))
  ) return "tablet";
  if (
    mobileHint === "?1" ||
    /mobile|iphone|ipod|android|windows phone/.test(normalized)
  ) return "mobile";
  return "desktop";
}

function requestCountry(request: Request): string {
  const country = request.cf?.country;
  return typeof country === "string" && /^[A-Za-z]{2}$/.test(country)
    ? country.toUpperCase()
    : "XX";
}

async function recordAnalytics(
  event: AnalyticsEvent,
  row: VideoRow,
  request: Request,
  env: Env,
): Promise<void> {
  const columns: Record<AnalyticsEvent, string> = {
    page_view: "page_views",
    play_start: "play_starts",
    play_complete: "play_completions",
  };
  const column = columns[event];
  const now = new Date();
  const accessDate = now.toISOString().slice(0, 10);
  const country = requestCountry(request);
  const device = classifyDevice(
    request.headers.get("User-Agent") ?? "",
    request.headers.get("Sec-CH-UA-Mobile") ?? "",
  );
  await env.DB.prepare(
    `INSERT INTO video_access_stats_daily (
      video_id, access_date, country_code, device_class, ${column}, updated_at
    ) VALUES (?, ?, ?, ?, 1, ?)
    ON CONFLICT(video_id, access_date, country_code, device_class)
    DO UPDATE SET ${column} = ${column} + 1, updated_at = excluded.updated_at`,
  ).bind(row.id, accessDate, country, device, now.toISOString()).run();
}

function constantTimeEqual(left: string, right: string): boolean {
  const size = Math.max(left.length, right.length);
  let mismatch = left.length ^ right.length;
  for (let index = 0; index < size; index++) {
    mismatch |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return mismatch === 0;
}

function isAuthorized(request: Request, env: Env): boolean {
  const header = request.headers.get("Authorization") ?? "";
  return header.startsWith("Bearer ") &&
    constantTimeEqual(header.slice(7), env.APP_API_TOKEN);
}

function hexToBase64(hex: string): string {
  const bytes = new Uint8Array(hex.match(/.{2}/g)!.map((value) =>
    parseInt(value, 16)
  ));
  let binary = "";
  bytes.forEach((byte) => binary += String.fromCharCode(byte));
  return btoa(binary);
}

function arrayBufferToHex(value: ArrayBuffer): string {
  return [...new Uint8Array(value)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function validateCreateBody(
  value: unknown,
  maxBytes: number,
): CreateVideoBody | null {
  if (!value || typeof value !== "object") return null;
  const body = value as Record<string, unknown>;
  if (
    typeof body.idempotency_key !== "string" ||
    body.idempotency_key.length < 16 ||
    body.idempotency_key.length > 128 ||
    body.content_type !== "video/mp4" ||
    !Number.isSafeInteger(body.size_bytes) ||
    Number(body.size_bytes) <= 0 ||
    Number(body.size_bytes) > maxBytes ||
    typeof body.sha256 !== "string" ||
    !/^[a-f0-9]{64}$/.test(body.sha256) ||
    (body.duration_seconds !== undefined &&
      (typeof body.duration_seconds !== "number" ||
        !Number.isFinite(body.duration_seconds) ||
        body.duration_seconds < 0))
  ) return null;
  return body as unknown as CreateVideoBody;
}

async function signUpload(row: VideoRow, env: Env) {
  const client = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });
  const endpoint =
    `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com/` +
    `${env.R2_BUCKET_NAME}/${row.object_key}?X-Amz-Expires=3600`;
  const headers = {
    "Content-Type": row.content_type,
    "x-amz-checksum-sha256": hexToBase64(row.sha256),
  };
  const signed = await client.sign(
    new Request(endpoint, { method: "PUT", headers }),
    { aws: { signQuery: true } },
  );
  return {
    upload_url: signed.url,
    upload_headers: headers,
    upload_expires_in: 3600,
  };
}

function publicFields(row: VideoRow, env: Env) {
  return {
    id: row.id,
    short_code: formatShortCode(row.short_code),
    public_url: `${env.PUBLIC_BASE_URL}/${formatShortCode(row.short_code)}`,
    object_key: row.object_key,
    status: row.status,
    expires_at: row.expires_at,
  };
}

async function createVideo(request: Request, env: Env): Promise<Response> {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const body = validateCreateBody(
    raw,
    Number(env.MAX_VIDEO_SIZE_BYTES || 1073741824),
  );
  if (!body) return json({ error: "invalid_video" }, 400);

  const existing = await env.DB.prepare(
    "SELECT * FROM videos WHERE idempotency_key = ?",
  ).bind(body.idempotency_key).first<VideoRow>();
  if (existing) {
    if (existing.sha256 !== body.sha256 || existing.size_bytes !== body.size_bytes) {
      return json({ error: "idempotency_conflict" }, 409);
    }
    if (["revoked", "expired", "deleted"].includes(existing.status)) {
      return json({ error: "resource_unavailable" }, 409);
    }
    const upload = existing.status === "available"
      ? {}
      : await signUpload(existing, env);
    return json({ ...publicFields(existing, env), ...upload });
  }

  const now = new Date();
  const retention = Number(env.VIDEO_RETENTION_DAYS || 0);
  const expiresAt = retention > 0
    ? new Date(now.getTime() + retention * 86400000).toISOString()
    : null;
  for (let attempt = 0; attempt < 32; attempt++) {
    const row: VideoRow = {
      id: crypto.randomUUID(),
      short_code: randomCode(),
      object_key: "",
      idempotency_key: body.idempotency_key,
      content_type: body.content_type,
      size_bytes: body.size_bytes,
      duration_seconds: body.duration_seconds ?? null,
      status: "pending",
      created_at: now.toISOString(),
      uploaded_at: null,
      expires_at: expiresAt,
      revoked_at: null,
      sha256: body.sha256,
      etag: null,
      upload_attempts: 1,
    };
    row.object_key = `videos/${row.id}.mp4`;
    try {
      await env.DB.prepare(
        `INSERT INTO videos (
          id, short_code, object_key, idempotency_key, content_type,
          size_bytes, duration_seconds, status, created_at, expires_at,
          sha256, upload_attempts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, 1)`,
      ).bind(
        row.id, row.short_code, row.object_key, row.idempotency_key,
        row.content_type, row.size_bytes, row.duration_seconds,
        row.created_at, row.expires_at, row.sha256,
      ).run();
      log("upload_created", { upload_id: row.id });
      return json({
        ...publicFields(row, env),
        ...await signUpload(row, env),
      }, 201);
    } catch (error) {
      if (!String(error).includes("UNIQUE")) throw error;
    }
  }
  return json({ error: "code_space_busy" }, 503);
}

async function findByID(id: string, env: Env): Promise<VideoRow | null> {
  return env.DB.prepare("SELECT * FROM videos WHERE id = ?")
    .bind(id).first<VideoRow>();
}

async function retryVideo(id: string, env: Env): Promise<Response> {
  const row = await findByID(id, env);
  if (!row) return json({ error: "not_found" }, 404);
  if (["available", "revoked", "expired", "deleted"].includes(row.status)) {
    return json({ error: "invalid_state", status: row.status }, 409);
  }
  await env.DB.prepare(
    `UPDATE videos SET status = 'uploading',
      upload_attempts = upload_attempts + 1, failure_reason = NULL WHERE id = ?`,
  ).bind(id).run();
  row.status = "uploading";
  return json({ ...publicFields(row, env), ...await signUpload(row, env) });
}

async function completeVideo(id: string, env: Env): Promise<Response> {
  const row = await findByID(id, env);
  if (!row) return json({ error: "not_found" }, 404);
  if (row.status === "available") return json(publicFields(row, env));
  if (["revoked", "expired", "deleted"].includes(row.status)) {
    return json({ error: "invalid_state" }, 409);
  }
  const object = await env.VIDEOS.head(row.object_key);
  if (!object) return json({ error: "object_missing" }, 409);
  const checksum = object.checksums.sha256
    ? arrayBufferToHex(object.checksums.sha256)
    : null;
  if (
    object.size !== row.size_bytes ||
    object.httpMetadata?.contentType !== row.content_type ||
    (checksum !== null && checksum !== row.sha256)
  ) {
    await env.DB.prepare(
      "UPDATE videos SET status = 'failed', failure_reason = ? WHERE id = ?",
    ).bind("integrity_mismatch", id).run();
    return json({ error: "integrity_mismatch" }, 409);
  }
  const uploadedAt = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE videos SET status = 'available', uploaded_at = ?,
      etag = ?, failure_reason = NULL WHERE id = ?`,
  ).bind(uploadedAt, object.httpEtag, id).run();
  row.status = "available";
  row.uploaded_at = uploadedAt;
  row.etag = object.httpEtag;
  log("upload_completed", { upload_id: id });
  return json(publicFields(row, env));
}

async function mutateVideo(
  id: string,
  operation: "revoke" | "delete",
  env: Env,
): Promise<Response> {
  const row = await findByID(id, env);
  if (!row) return json({ error: "not_found" }, 404);
  const now = new Date().toISOString();
  if (operation === "revoke") {
    await env.DB.prepare(
      "UPDATE videos SET status = 'revoked', revoked_at = ? WHERE id = ?",
    ).bind(now, id).run();
    log("video_revoked", { upload_id: id });
  } else {
    await env.VIDEOS.delete(row.object_key);
    await env.DB.prepare(
      "UPDATE videos SET status = 'deleted', deleted_at = ? WHERE id = ?",
    ).bind(now, id).run();
    log("video_deleted", { upload_id: id });
  }
  return json({ id, status: operation === "revoke" ? "revoked" : "deleted" });
}

async function rowForCode(code: string, env: Env): Promise<VideoRow | null> {
  return env.DB.prepare("SELECT * FROM videos WHERE short_code = ?")
    .bind(code).first<VideoRow>();
}

function unavailablePage(): Response {
  return new Response(
    page("Conteúdo indisponível", "Este conteúdo não está mais disponível.", null),
    { status: 410, headers: pageHeaders },
  );
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

export function page(
  title: string,
  message: string,
  code: string | null,
  professionalSignature = "",
): string {
  const video = code
    ? `<div class="player"><video id="video" controls playsinline preload="metadata"
         src="/media/${formatShortCode(code)}"></video>
       <div id="loading">Carregando vídeo…</div>
       <div id="error" hidden>Não foi possível reproduzir este vídeo.</div></div>`
    : "";
  const heading = code ? "" : `<h1>${title}</h1>`;
  const signature = code && professionalSignature
    ? `<p class="signature">${escapeHTML(professionalSignature)}</p>`
    : "";
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex,nofollow,noarchive"><title>${title}</title>
  <style>*{box-sizing:border-box}body{margin:0;background:#101216;color:#f5f6f8;
  font:16px -apple-system,BlinkMacSystemFont,sans-serif;min-height:100dvh}
  main{width:100%;padding:2px;text-align:center}.player{position:relative}
  video{display:block;width:100%;height:auto;background:#000;border-radius:8px;
  box-shadow:0 10px 32px #0008}.copy{margin:7px 8px 4px}
  p{margin:0;color:#b7bdc8;line-height:1.35}.signature{margin-top:3px;
  color:#858c98;font-size:12px;line-height:1.3}#loading,#error{margin:8px}
  h1{margin:16px}
  @media(min-width:700px){body{display:grid;place-items:center}
  main{width:min(920px,96vw);padding:8px}video{width:auto;max-width:100%;
  max-height:calc(100vh - 92px);margin:auto;border-radius:12px}}</style>
  </head><body><main>${heading}${video}<div class="copy"><p>${message}</p>
  ${signature}</div></main><script>const v=document.getElementById("video");
  if(v){const l=document.getElementById("loading"),e=document.getElementById("error");
  v.addEventListener("loadeddata",()=>l.hidden=true);v.addEventListener("error",()=>{
  l.hidden=true;e.hidden=false});let started=false,completed=false;
  const metric=event=>fetch("/analytics/${code}/"+event,{method:"POST",
  credentials:"omit",keepalive:true}).catch(()=>{});
  v.addEventListener("play",()=>{if(!started){started=true;metric("play")}});
  v.addEventListener("ended",()=>{if(!completed){completed=true;metric("complete")}})
  }</script></body></html>`;
}

async function publicPage(
  request: Request,
  code: string,
  env: Env,
  ctx: ExecutionContext,
) {
  const row = await rowForCode(code, env);
  if (!row) return new Response("Not Found", { status: 404, headers: pageHeaders });
  if (row.status !== "available" ||
      (row.expires_at && row.expires_at <= new Date().toISOString())) {
    return unavailablePage();
  }
  ctx.waitUntil((async () => {
    await env.DB.prepare(
      `UPDATE videos SET access_count = access_count + 1,
        last_accessed_at = ? WHERE id = ?`,
    ).bind(new Date().toISOString(), row.id).run();
    await recordAnalytics("page_view", row, request, env);
  })());
  log("video_accessed", { upload_id: row.id });
  return new Response(
    page(
      "Vídeo do laudo",
      "Este vídeo é um material complementar ao laudo médico e não substitui sua leitura integral.",
      code,
      env.PROFESSIONAL_SIGNATURE,
    ),
    { headers: pageHeaders },
  );
}

async function analytics(
  request: Request,
  code: string,
  event: "play" | "complete",
  env: Env,
): Promise<Response> {
  const origin = request.headers.get("Origin");
  if (origin !== env.PUBLIC_BASE_URL) {
    return new Response(null, { status: 403, headers: pageHeaders });
  }
  const row = await rowForCode(code, env);
  if (!row || row.status !== "available" ||
      (row.expires_at && row.expires_at <= new Date().toISOString())) {
    return new Response(null, { status: 404, headers: pageHeaders });
  }
  await recordAnalytics(
    event === "play" ? "play_start" : "play_complete",
    row,
    request,
    env,
  );
  return new Response(null, {
    status: 204,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Robots-Tag": "noindex, nofollow, noarchive",
    },
  });
}

async function videoStats(row: VideoRow, env: Env): Promise<Response> {
  const totals = await env.DB.prepare(
    `SELECT
      COALESCE(SUM(page_views), 0) AS page_views,
      COALESCE(SUM(play_starts), 0) AS play_starts,
      COALESCE(SUM(play_completions), 0) AS play_completions
    FROM video_access_stats_daily WHERE video_id = ?`,
  ).bind(row.id).first();
  const daily = await env.DB.prepare(
    `SELECT access_date, country_code, device_class, page_views,
      play_starts, play_completions
    FROM video_access_stats_daily WHERE video_id = ?
    ORDER BY access_date DESC, country_code, device_class LIMIT 500`,
  ).bind(row.id).all();
  return json({
    short_code: formatShortCode(row.short_code),
    totals,
    daily: daily.results,
  });
}

async function recentVideoStats(url: URL, env: Env): Promise<Response> {
  const limit = parseRecentStatsLimit(url.searchParams.get("limit"));
  if (limit === null) return json({ error: "invalid_limit" }, 400);

  const videos = await env.DB.prepare(
    `SELECT
      v.short_code,
      v.status,
      v.created_at,
      COALESCE(SUM(s.page_views), 0) AS page_views,
      COALESCE(SUM(s.play_starts), 0) AS play_starts,
      COALESCE(SUM(s.play_completions), 0) AS play_completions
    FROM videos v
    LEFT JOIN video_access_stats_daily s ON s.video_id = v.id
    GROUP BY v.id, v.short_code, v.status, v.created_at
    ORDER BY v.created_at DESC
    LIMIT ?`,
  ).bind(limit).all<{
    short_code: string;
    status: VideoStatus;
    created_at: string;
    page_views: number;
    play_starts: number;
    play_completions: number;
  }>();

  return json({
    limit,
    videos: videos.results.map((video) => ({
      ...video,
      short_code: formatShortCode(video.short_code),
    })),
  });
}

async function media(request: Request, code: string, env: Env) {
  const row = await rowForCode(code, env);
  if (!row || row.status !== "available" ||
      (row.expires_at && row.expires_at <= new Date().toISOString())) {
    return new Response(null, { status: 404, headers: pageHeaders });
  }
  try {
    const rangeHeader = request.headers.get("Range");
    let requestedRange: { offset: number; length: number } | undefined;
    if (rangeHeader) {
      const match = rangeHeader.match(/^bytes=(\d*)-(\d*)$/);
      if (!match || (!match[1] && !match[2])) throw new Error("invalid_range");
      if (!match[1]) {
        const suffix = Math.min(Number(match[2]), row.size_bytes);
        requestedRange = { offset: row.size_bytes - suffix, length: suffix };
      } else {
        const offset = Number(match[1]);
        const end = match[2] ? Number(match[2]) : row.size_bytes - 1;
        if (offset > end || offset >= row.size_bytes) throw new Error("invalid_range");
        requestedRange = {
          offset,
          length: Math.min(end, row.size_bytes - 1) - offset + 1,
        };
      }
    }
    const object = await env.VIDEOS.get(row.object_key, {
      range: requestedRange,
    });
    if (!object || !("body" in object)) {
      return new Response(null, { status: object ? 412 : 404 });
    }
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("Accept-Ranges", "bytes");
    headers.set("ETag", object.httpEtag);
    headers.set("Cache-Control", "private, no-store");
    headers.set("X-Content-Type-Options", "nosniff");
    headers.set("X-Robots-Tag", "noindex, nofollow, noarchive");
    let status = 200;
    if (requestedRange) {
      status = 206;
      const { offset, length } = requestedRange;
      headers.set(
        "Content-Range",
        `bytes ${offset}-${offset + length - 1}/${row.size_bytes}`,
      );
      headers.set("Content-Length", String(length));
    } else {
      headers.set("Content-Length", String(object.size));
    }
    return new Response(object.body, { status, headers });
  } catch {
    return new Response(null, {
      status: 416,
      headers: { "Content-Range": `bytes */${row.size_bytes}` },
    });
  }
}

async function api(request: Request, url: URL, env: Env): Promise<Response> {
  if (!isAuthorized(request, env)) return json({ error: "unauthorized" }, 401);
  if (request.method === "GET" && url.pathname === "/api/stats/recent") {
    return recentVideoStats(url, env);
  }
  if (request.method === "GET" && url.pathname === "/api/stats") {
    const code = normalizeShortCode(url.searchParams.get("code") ?? "");
    if (!code) return json({ error: "invalid_code" }, 400);
    const row = await rowForCode(code, env);
    return row ? videoStats(row, env) : json({ error: "not_found" }, 404);
  }
  if (request.method === "POST" && url.pathname === "/api/videos") {
    return createVideo(request, env);
  }
  const match = url.pathname.match(
    /^\/api\/videos\/([0-9a-f-]+)(?:\/(complete|retry|revoke|status|stats))?$/,
  );
  if (!match) return json({ error: "not_found" }, 404);
  const [, id, action] = match;
  if (request.method === "POST" && action === "complete") {
    return completeVideo(id, env);
  }
  if (request.method === "POST" && action === "retry") {
    return retryVideo(id, env);
  }
  if (request.method === "POST" && action === "revoke") {
    return mutateVideo(id, "revoke", env);
  }
  if (request.method === "DELETE" && !action) {
    return mutateVideo(id, "delete", env);
  }
  if (request.method === "GET" && action === "status") {
    const row = await findByID(id, env);
    return row ? json(publicFields(row, env)) : json({ error: "not_found" }, 404);
  }
  if (request.method === "GET" && action === "stats") {
    const row = await findByID(id, env);
    return row ? videoStats(row, env) : json({ error: "not_found" }, 404);
  }
  return json({ error: "method_not_allowed" }, 405);
}

async function handle(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const requestID = request.headers.get("cf-ray") ?? crypto.randomUUID();
  try {
    if (request.method === "GET" && url.pathname === "/__health") {
      return json({ service: "skjaldr-video", status: "ok" });
    }
    if (url.pathname.startsWith("/api/")) return api(request, url, env);
    const analyticsMatch = url.pathname.match(
      /^\/analytics\/([^/]+)\/(play|complete)$/,
    );
    if (analyticsMatch) {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { ...pageHeaders, Allow: "POST" },
        });
      }
      const code = normalizeShortCode(analyticsMatch[1]);
      if (!code) {
        return new Response("Not Found", { status: 404, headers: pageHeaders });
      }
      if (env.PUBLIC_RATE_LIMITER) {
        const actor = request.headers.get("cf-connecting-ip") ?? "unknown";
        const allowed = await env.PUBLIC_RATE_LIMITER.limit({ key: actor });
        if (!allowed.success) {
          return new Response("Too Many Requests", {
            status: 429,
            headers: { ...pageHeaders, "Retry-After": "60" },
          });
        }
      }
      return analytics(request, code, analyticsMatch[2] as "play" | "complete", env);
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { ...pageHeaders, Allow: "GET, HEAD" },
      });
    }
    const mediaMatch = url.pathname.match(/^\/media\/([^/]+)$/);
    const rawCode = mediaMatch?.[1] ?? url.pathname.slice(1);
    const code = normalizeShortCode(rawCode);
    if (!code) return new Response("Not Found", { status: 404, headers: pageHeaders });
    if (env.PUBLIC_RATE_LIMITER) {
      const actor = request.headers.get("cf-connecting-ip") ?? "unknown";
      const allowed = await env.PUBLIC_RATE_LIMITER.limit({ key: actor });
      if (!allowed.success) return new Response("Too Many Requests", {
        status: 429,
        headers: { ...pageHeaders, "Retry-After": "60" },
      });
    }
    return mediaMatch ? media(request, code, env) : publicPage(request, code, env, ctx);
  } catch (error) {
    log("request_failed", { request_id: requestID, message: String(error) });
    return json({ error: "internal_error", request_id: requestID }, 500);
  }
}

async function cleanup(env: Env): Promise<void> {
  const now = new Date().toISOString();
  const expired = await env.DB.prepare(
    `SELECT * FROM videos WHERE status = 'available'
      AND expires_at IS NOT NULL AND expires_at <= ? LIMIT 100`,
  ).bind(now).all<VideoRow>();
  for (const row of expired.results) {
    await env.VIDEOS.delete(row.object_key);
    await env.DB.prepare(
      "UPDATE videos SET status = 'expired' WHERE id = ?",
    ).bind(row.id).run();
  }
  await env.DB.prepare(
    `UPDATE videos SET status = 'failed', failure_reason = 'upload_abandoned'
      WHERE status IN ('pending', 'uploading')
      AND created_at < datetime('now', '-1 day')`,
  ).run();
  const analyticsRetention = Math.max(
    1,
    Number(env.ANALYTICS_RETENTION_DAYS || 30),
  );
  await env.DB.prepare(
    "DELETE FROM video_access_stats_daily WHERE access_date < date('now', ?)",
  ).bind(`-${analyticsRetention} days`).run();
}

export default {
  fetch: handle,
  scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(cleanup(env));
  },
} satisfies ExportedHandler<Env>;
