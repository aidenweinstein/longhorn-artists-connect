import { createHash, createHmac } from "node:crypto";

/**
 * Cloudflare R2: where every file posted from the website is uploaded. Browsers can't
 * upload to CloudKit (Apple's upload server sends no CORS headers), so the browser sends
 * each file straight to R2. Small files then move on to CloudKit from the server, which
 * CORS doesn't apply to; files too big for CloudKit Web Services (over 50 MB, such as
 * films at full quality, up to 10 GB) stay in R2, and the post's CloudKit record keeps a
 * link to them (filmVideoURL and the like).
 *
 * R2 speaks the S3 API. Requests are signed here with AWS Signature V4 so the site
 * needs no extra packages. Settings (Vercel and .env.local):
 *   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET,
 *   R2_PUBLIC_URL  (the bucket's public address, e.g. https://media.nexusbylac.com)
 */

type R2Config = { accountID: string; accessKeyID: string; secret: string; bucket: string; publicURL: string };

function config(): R2Config | null {
  const accountID = process.env.R2_ACCOUNT_ID ?? "";
  const accessKeyID = process.env.R2_ACCESS_KEY_ID ?? "";
  const secret = process.env.R2_SECRET_ACCESS_KEY ?? "";
  const bucket = process.env.R2_BUCKET ?? "";
  const publicURL = (process.env.R2_PUBLIC_URL ?? "").replace(/\/+$/, "");
  return accountID && accessKeyID && secret && bucket && /^https:\/\//.test(publicURL)
    ? { accountID, accessKeyID, secret, bucket, publicURL }
    : null;
}

export function isR2Configured(): boolean {
  return config() !== null;
}

/** The public address a finished upload plays from. */
export function publicURLFor(key: string): string {
  const c = config();
  if (!c) throw new Error("R2 isn't configured.");
  return `${c.publicURL}/${encodePath(key)}`;
}

/** The storage key behind one of this bucket's public addresses, or null for any other address. */
export function keyFromPublicURL(url: string): string | null {
  const c = config();
  if (!c || !url.startsWith(`${c.publicURL}/`)) return null;
  try {
    return url.slice(c.publicURL.length + 1).split("/").map(decodeURIComponent).join("/");
  } catch {
    return null;
  }
}

// MARK: - Signature V4

const REGION = "auto";
const SERVICE = "s3";

/** RFC 3986 encoding, as S3 signing expects (encodeURIComponent leaves !'()* alone). */
const encode = (s: string) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
const encodePath = (key: string) => key.split("/").map(encode).join("/");
const sha256 = (data: string | Buffer) => createHash("sha256").update(data).digest("hex");
const hmac = (key: string | Buffer, data: string) => createHmac("sha256", key).update(data).digest();

function stamps(now: Date) {
  const amzDate = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  return { amzDate, day: amzDate.slice(0, 8) };
}

function signature(secret: string, day: string, stringToSign: string): string {
  const key = hmac(hmac(hmac(hmac(`AWS4${secret}`, day), REGION), SERVICE), "aws4_request");
  return createHmac("sha256", key).update(stringToSign).digest("hex");
}

function canonicalQuery(query: Record<string, string>): string {
  return Object.keys(query)
    .sort()
    .map((k) => `${encode(k)}=${encode(query[k])}`)
    .join("&");
}

type Signable = {
  method: string;
  host: string;
  path: string;
  query: Record<string, string>;
  headers: Record<string, string>;
  payloadHash: string;
  accessKeyID: string;
  secret: string;
  now: Date;
};

/** The signature for one request. Header names must already be lowercase. */
export function signRequest(r: Signable): { signature: string; signedHeaders: string; scope: string } {
  const { amzDate, day } = stamps(r.now);
  const scope = `${day}/${REGION}/${SERVICE}/aws4_request`;
  const names = Object.keys(r.headers).sort();
  const signedHeaders = names.join(";");
  const canonical = [
    r.method,
    r.path,
    canonicalQuery(r.query),
    names.map((n) => `${n}:${r.headers[n].trim()}\n`).join(""),
    signedHeaders,
    r.payloadHash,
  ].join("\n");
  const stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256(canonical)].join("\n");
  return { signature: signature(r.secret, day, stringToSign), signedHeaders, scope };
}

/** A URL anyone holding it can use for one request until it expires (query-string signing). */
export function presign(
  c: { host: string; accessKeyID: string; secret: string },
  method: string,
  path: string,
  query: Record<string, string>,
  expiresSeconds: number,
  now = new Date(),
  /** Extra headers the request must carry exactly (lowercase names), e.g. content-length. */
  signedHeaders: Record<string, string> = {},
): string {
  const headers = { ...signedHeaders, host: c.host };
  const { amzDate, day } = stamps(now);
  const full: Record<string, string> = {
    ...query,
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${c.accessKeyID}/${day}/${REGION}/${SERVICE}/aws4_request`,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(expiresSeconds),
    "X-Amz-SignedHeaders": Object.keys(headers).sort().join(";"),
  };
  const { signature } = signRequest({
    method, host: c.host, path, query: full, headers, payloadHash: "UNSIGNED-PAYLOAD",
    accessKeyID: c.accessKeyID, secret: c.secret, now,
  });
  return `https://${c.host}${path}?${canonicalQuery({ ...full, "X-Amz-Signature": signature })}`;
}

// MARK: - Requests

function endpoint(c: R2Config) {
  return { host: `${c.accountID}.r2.cloudflarestorage.com`, accessKeyID: c.accessKeyID, secret: c.secret };
}

async function send(method: string, key: string, query: Record<string, string>, body = "", extra: Record<string, string> = {}): Promise<Response> {
  const c = config();
  if (!c) throw new Error("R2 isn't configured.");
  const { host } = endpoint(c);
  const path = key ? `/${encode(c.bucket)}/${encodePath(key)}` : `/${encode(c.bucket)}`;
  const now = new Date();
  const payloadHash = sha256(body);
  const headers: Record<string, string> = { host, "x-amz-content-sha256": payloadHash, "x-amz-date": stamps(now).amzDate, ...extra };
  const { signature, signedHeaders, scope } = signRequest({ method, host, path, query, headers, payloadHash, accessKeyID: c.accessKeyID, secret: c.secret, now });
  const qs = canonicalQuery(query);
  const { host: _host, ...sendHeaders } = headers;
  void _host;
  return fetch(`https://${host}${path}${qs ? `?${qs}` : ""}`, {
    method,
    headers: { ...sendHeaders, authorization: `AWS4-HMAC-SHA256 Credential=${c.accessKeyID}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}` },
    body: body || undefined,
    cache: "no-store",
  });
}

async function check(res: Response, what: string): Promise<string> {
  const text = await res.text();
  if (!res.ok) throw new Error(`R2 ${what} failed (${res.status}): ${text.slice(0, 300)}`);
  return text;
}

const xmlEscape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** Starts a multipart upload; the parts then go up from the browser to presigned URLs. */
export async function createMultipartUpload(key: string, contentType: string): Promise<string> {
  const xml = await check(await send("POST", key, { uploads: "" }, "", { "content-type": contentType }), "start upload");
  const uploadID = /<UploadId>([^<]+)<\/UploadId>/.exec(xml)?.[1];
  if (!uploadID) throw new Error("R2 didn't return an upload ID.");
  return uploadID;
}

/**
 * Presigned URLs for each part of a multipart upload, one per entry in `partSizes`. Each
 * URL is locked to its part's exact byte count (a signed Content-Length), so nobody can
 * push more through it than the file they declared.
 */
export function partUploadURLs(key: string, uploadID: string, partSizes: number[], expiresSeconds: number): string[] {
  const c = config();
  if (!c) throw new Error("R2 isn't configured.");
  const path = `/${encode(c.bucket)}/${encodePath(key)}`;
  const now = new Date();
  return partSizes.map((size, i) =>
    presign(endpoint(c), "PUT", path, { partNumber: String(i + 1), uploadId: uploadID }, expiresSeconds, now, {
      "content-length": String(size),
    }),
  );
}

const tag = (xml: string, name: string) => new RegExp(`<${name}>([^<]*)</${name}>`).exec(xml)?.[1];
const blocks = (xml: string, name: string) => xml.match(new RegExp(`<${name}>[\\s\\S]*?</${name}>`, "g")) ?? [];

/** Stored files under a prefix: key, size in bytes, and when each was stored. */
export async function listObjects(prefix: string): Promise<{ key: string; size: number; modified: number }[]> {
  const out: { key: string; size: number; modified: number }[] = [];
  let token: string | undefined;
  for (let page = 0; page < 50; page++) {
    const query: Record<string, string> = { "list-type": "2", prefix, "max-keys": "1000", ...(token ? { "continuation-token": token } : {}) };
    const xml = await check(await send("GET", "", query), "list files");
    for (const b of blocks(xml, "Contents")) {
      out.push({ key: tag(b, "Key") ?? "", size: Number(tag(b, "Size") ?? 0), modified: Date.parse(tag(b, "LastModified") ?? "") || 0 });
    }
    token = tag(xml, "IsTruncated") === "true" ? tag(xml, "NextContinuationToken") : undefined;
    if (!token) break;
  }
  return out;
}

/** Uploads under a prefix that were started but not finished: key, and when each started. */
export async function listUnfinishedUploads(prefix: string): Promise<{ key: string; started: number }[]> {
  const out: { key: string; started: number }[] = [];
  let keyMarker: string | undefined;
  let idMarker: string | undefined;
  for (let page = 0; page < 50; page++) {
    const query: Record<string, string> = {
      uploads: "",
      prefix,
      "max-uploads": "1000",
      ...(keyMarker ? { "key-marker": keyMarker } : {}),
      ...(idMarker ? { "upload-id-marker": idMarker } : {}),
    };
    const xml = await check(await send("GET", "", query), "list uploads");
    for (const b of blocks(xml, "Upload")) {
      out.push({ key: tag(b, "Key") ?? "", started: Date.parse(tag(b, "Initiated") ?? "") || 0 });
    }
    if (tag(xml, "IsTruncated") !== "true") break;
    keyMarker = tag(xml, "NextKeyMarker");
    idMarker = tag(xml, "NextUploadIdMarker");
    if (!keyMarker) break;
  }
  return out;
}

export async function completeMultipartUpload(key: string, uploadID: string, parts: { partNumber: number; etag: string }[]): Promise<void> {
  const body =
    "<CompleteMultipartUpload>" +
    parts.map((p) => `<Part><PartNumber>${p.partNumber}</PartNumber><ETag>${xmlEscape(p.etag)}</ETag></Part>`).join("") +
    "</CompleteMultipartUpload>";
  const text = await check(await send("POST", key, { uploadId: uploadID }, body, { "content-type": "application/xml" }), "finish upload");
  // S3 can answer 200 with an error inside.
  if (/<Error>/.test(text)) throw new Error(`R2 finish upload failed: ${text.slice(0, 300)}`);
}

export async function abortMultipartUpload(key: string, uploadID: string): Promise<void> {
  await send("DELETE", key, { uploadId: uploadID }).catch(() => undefined);
}

/** The stored file's size in bytes, or null when it isn't there. */
export async function objectSize(key: string): Promise<number | null> {
  const res = await send("HEAD", key, {});
  if (!res.ok) return null;
  const n = Number(res.headers.get("content-length"));
  return Number.isFinite(n) ? n : null;
}

/** A stored file's bytes and type (for small files on their way to CloudKit). */
export async function getObject(key: string): Promise<{ bytes: Uint8Array; contentType: string }> {
  const res = await send("GET", key, {});
  if (!res.ok) throw new Error(`R2 read failed (${res.status}): ${(await res.text()).slice(0, 300)}`);
  return { bytes: new Uint8Array(await res.arrayBuffer()), contentType: res.headers.get("content-type") || "application/octet-stream" };
}

export async function deleteObject(key: string): Promise<void> {
  await send("DELETE", key, {}).catch(() => undefined);
}
