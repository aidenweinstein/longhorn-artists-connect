import { randomInt, randomUUID } from "node:crypto";

/**
 * Talks to verification-service's /v1/web/session/* endpoints. Server-only:
 * WEB_CLIENT_TOKEN must never reach the browser.
 *
 * Without VERIFICATION_URL in development, a local stand-in prints each code
 * to the terminal running `npm run dev` so the flow can be tested end to end.
 */

export type RequestResult =
  | { ok: true; pendingID: string; schoolName: string }
  | { ok: false; message: string };

export type ConfirmResult =
  | { ok: true; email: string; schoolID: string; schoolName: string; domainKind: string; userRecordName?: string }
  | { ok: false; message: string };

const workerURL = () => process.env.VERIFICATION_URL?.replace(/\/$/, "");
const isDevStandIn = () => !workerURL() && process.env.NODE_ENV !== "production";

async function callWorker(path: string, body: unknown, clientIP: string) {
  const url = workerURL();
  const token = process.env.WEB_CLIENT_TOKEN;
  if (!url || !token) {
    return { status: 503, json: { message: "Sign-in isn't set up yet. Try again later." } as Record<string, unknown> };
  }
  const res = await fetch(`${url}${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
      "x-nexus-client-ip": clientIP,
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  return { status: res.status, json: (await res.json().catch(() => ({}))) as Record<string, unknown> };
}

export async function requestCode(email: string, clientIP: string): Promise<RequestResult> {
  if (isDevStandIn()) return devRequest(email);
  const { status, json } = await callWorker("/v1/web/session/request", { email }, clientIP);
  if (status !== 200) return { ok: false, message: String(json.message ?? "Couldn't send a code. Try again.") };
  const school = json.school as { name?: string } | undefined;
  return { ok: true, pendingID: String(json.pendingID), schoolName: school?.name ?? "" };
}

export async function confirmCode(pendingID: string, code: string, clientIP: string): Promise<ConfirmResult> {
  if (isDevStandIn()) return devConfirm(pendingID, code);
  const { status, json } = await callWorker("/v1/web/session/confirm", { pendingID, code }, clientIP);
  if (status !== 200) return { ok: false, message: String(json.message ?? "That code isn't valid.") };
  return {
    ok: true,
    email: String(json.email),
    schoolID: String(json.schoolID),
    schoolName: String(json.schoolName ?? ""),
    domainKind: String(json.domainKind ?? "student"),
    userRecordName: typeof json.userRecordName === "string" ? json.userRecordName : undefined,
  };
}

// MARK: - Development stand-in

type DevPending = { email: string; code: string; expiresAt: number; attempts: number };
const devStore = ((globalThis as { __nexusDevCodes?: Map<string, DevPending> }).__nexusDevCodes ??= new Map());

function devRequest(email: string): RequestResult {
  const normalized = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.edu$/.test(normalized)) {
    return { ok: false, message: "Use your school (.edu) email address." };
  }
  const pendingID = randomUUID();
  const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
  devStore.set(pendingID, { email: normalized, code, expiresAt: Date.now() + 600_000, attempts: 0 });
  console.log(`\n[nexus dev] Sign-in code for ${normalized}: ${code}\n`);
  return { ok: true, pendingID, schoolName: "your school" };
}

function devConfirm(pendingID: string, code: string): ConfirmResult {
  const pending = devStore.get(pendingID);
  if (!pending || pending.expiresAt < Date.now()) return { ok: false, message: "That code expired. Request a new one." };
  if (++pending.attempts > 5) return { ok: false, message: "Too many wrong codes. Request a new one." };
  if (pending.code !== code) return { ok: false, message: "That code isn't valid." };
  devStore.delete(pendingID);
  return { ok: true, email: pending.email, schoolID: "dev", schoolName: "Development", domainKind: "student" };
}
