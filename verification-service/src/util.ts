/// Shared helpers: hashing, email normalisation, domain matching, rate limits.

export interface Env {
    DB: D1Database;
    CK_CONTAINER: string;
    CK_ENVIRONMENT: string;
    MAIL_FROM: string;
    MAIL_FROM_NAME: string;
    SWEEP_ACTION: string;
    /// Unix seconds. Records created before this are exempt from the sweep,
    /// so existing users aren't wiped out the night verification ships.
    SWEEP_GRANDFATHER_BEFORE: string;
    APP_ATTEST_REQUIRED: string;
    /// School slug assigned by the schoolID backfill to posts whose creator has
    /// no verification on file — i.e. the grandfathered accounts. Must match
    /// `SchoolScope.legacyDefault` in the app.
    BACKFILL_DEFAULT_SCHOOL: string;
    CK_KEY_ID: string;
    CK_PRIVATE_KEY: string;
    CODE_PEPPER: string;
    RESEND_API_KEY: string;
    /// Bearer token for /v1/admin/*. Unset disables those routes entirely.
    ADMIN_TOKEN: string;
    /// Bearer token the website presents on /v1/web/*. Unset disables them.
    WEB_CLIENT_TOKEN: string;
}

export function json(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
    });
}

export function errorResponse(code: string, message: string, status: number): Response {
    return json({ error: code, message }, status);
}

export function nowSeconds(): number {
    return Math.floor(Date.now() / 1000);
}

// MARK: - Hashing

export async function sha256Base64(data: ArrayBuffer | Uint8Array): Promise<string> {
    const source = data instanceof Uint8Array ? toArrayBuffer(data) : data;
    const digest = await crypto.subtle.digest("SHA-256", source);
    return base64Encode(new Uint8Array(digest));
}

/// HMAC-SHA256, hex encoded. Used for both the code hash and the email hash so
/// that a dump of D1 alone never reveals a verification code or an address.
export async function hmacHex(secret: string, message: string): Promise<string> {
    const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
    );
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
    return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// Length-independent comparison. Both inputs here are fixed-length hex
/// digests, so comparing lengths first leaks nothing.
export function constantTimeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
        diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return diff === 0;
}

export function base64Encode(bytes: Uint8Array): string {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary);
}

export function base64Decode(value: string): Uint8Array {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
}

function toArrayBuffer(view: Uint8Array): ArrayBuffer {
    return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength) as ArrayBuffer;
}

// MARK: - Random

/// Six-digit code drawn without modulo bias.
export function randomCode(): string {
    const max = 1_000_000;
    const limit = Math.floor(0xffffffff / max) * max;
    const buf = new Uint32Array(1);
    let value: number;
    do {
        crypto.getRandomValues(buf);
        value = buf[0];
    } while (value >= limit);
    return String(value % max).padStart(6, "0");
}

export function randomToken(byteLength = 24): string {
    const bytes = new Uint8Array(byteLength);
    crypto.getRandomValues(bytes);
    return base64Encode(bytes).replace(/[+/=]/g, (c) => ({ "+": "-", "/": "_", "=": "" })[c]!);
}

// MARK: - Email

/// Lowercase and strip a `+tag`. Deliberately conservative: we do NOT strip
/// dots, because unlike Gmail many university mail systems treat
/// first.last@ and firstlast@ as different people.
export function normalizeEmail(raw: string): string | null {
    const trimmed = raw.trim().toLowerCase();
    if (trimmed.length < 6 || trimmed.length > 254) return null;
    if (!/^[^\s@]+@[^\s@]+\.[a-z]{2,}$/.test(trimmed)) return null;

    const [local, domain] = trimmed.split("@");
    const untagged = local.split("+")[0];
    if (untagged.length === 0) return null;
    return `${untagged}@${domain}`;
}

export function domainOf(email: string): string {
    return email.slice(email.indexOf("@") + 1);
}

/// Progressive suffixes of a hostname, most specific first:
/// "mail.grad.utexas.edu" -> ["mail.grad.utexas.edu", "grad.utexas.edu", "utexas.edu"]
/// Stops before the bare TLD so a stray "edu" row can never match everything.
export function domainCandidates(domain: string): string[] {
    const parts = domain.split(".");
    const out: string[] = [];
    for (let i = 0; i <= parts.length - 2; i++) {
        out.push(parts.slice(i).join("."));
    }
    return out;
}

// MARK: - Rate limiting

export interface RateLimitRule {
    dimension: string;
    value: string;
    limit: number;
    windowSeconds: number;
}

/// Fixed-window counter in D1. Returns true when the caller is over the limit.
/// Checked-and-incremented in one statement so concurrent requests can't race
/// past the ceiling.
export async function isRateLimited(env: Env, rule: RateLimitRule): Promise<boolean> {
    const now = nowSeconds();
    const windowStart = now - (now % rule.windowSeconds);
    const bucket = `${rule.dimension}:${rule.value}:${windowStart}`;

    const row = await env.DB.prepare(
        `INSERT INTO rate_limits (bucket, count, window_start) VALUES (?, 1, ?)
         ON CONFLICT(bucket) DO UPDATE SET count = count + 1
         RETURNING count`,
    )
        .bind(bucket, windowStart)
        .first<{ count: number }>();

    return (row?.count ?? 0) > rule.limit;
}

export async function checkAllRateLimits(env: Env, rules: RateLimitRule[]): Promise<string | null> {
    for (const rule of rules) {
        if (await isRateLimited(env, rule)) return rule.dimension;
    }
    return null;
}

export function clientIP(request: Request): string {
    return request.headers.get("cf-connecting-ip") ?? "unknown";
}
