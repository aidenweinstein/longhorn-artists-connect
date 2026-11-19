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
  | {
      ok: true;
      email: string;
      schoolID: string;
      schoolName: string;
      domainKind: string;
      userRecordName?: string;
      accountToken?: string;
      /** Sign in with Apple came first: whether its Apple ID is now linked, and whether this email just verified the app account. */
      apple?: { linked: boolean; verifiedApp: boolean };
    }
  | { ok: false; message: string; error?: string };

/** Sign in with Apple (lib/apple.ts): straight in, or the school email step with a ticket. */
export type AppleSessionResult =
  | { ok: true; signedIn: { email: string; schoolID: string; schoolName: string; domainKind: string; userRecordName: string } }
  | { ok: true; signedIn?: undefined; appleTicket: string; reason: "new" | "verify" | "confirm" }
  | { ok: false; message: string };

/** `role: "educator"` makes a Professor account, which has no graduation year. */
export type AccountDetails = { firstName: string; lastName: string; major: string; graduationYear: string; userTypes?: string; role?: "educator" };

export type CreateAccountResult =
  | { ok: true; userRecordName: string }
  | { ok: false; message: string; signInAgain?: boolean };

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

/** `purpose: "guest"` confirms any email address, not a school one, and can never lead to an account. */
export async function requestCode(email: string, clientIP: string, purpose?: "guest"): Promise<RequestResult> {
  if (isDevStandIn()) return devRequest(email, purpose);
  const { status, json } = await callWorker("/v1/web/session/request", { email, ...(purpose ? { purpose } : {}) }, clientIP);
  if (status !== 200) return { ok: false, message: String(json.message ?? "Couldn't send a code. Try again.") };
  const school = json.school as { name?: string } | undefined;
  return { ok: true, pendingID: String(json.pendingID), schoolName: school?.name ?? "" };
}

export async function confirmCode(pendingID: string, code: string, clientIP: string, appleTicket?: string): Promise<ConfirmResult> {
  if (isDevStandIn()) return devConfirm(pendingID, code);
  const { status, json } = await callWorker("/v1/web/session/confirm", { pendingID, code, ...(appleTicket ? { appleTicket } : {}) }, clientIP);
  if (status !== 200) return { ok: false, message: String(json.message ?? "That code isn't valid."), error: typeof json.error === "string" ? json.error : undefined };
  const apple = json.apple as { linked?: boolean; verifiedApp?: boolean } | undefined;
  return {
    ok: true,
    email: String(json.email),
    schoolID: String(json.schoolID),
    schoolName: String(json.schoolName ?? ""),
    domainKind: String(json.domainKind ?? "student"),
    userRecordName: typeof json.userRecordName === "string" ? json.userRecordName : undefined,
    accountToken: typeof json.accountToken === "string" ? json.accountToken : undefined,
    apple: apple ? { linked: !!apple.linked, verifiedApp: !!apple.verifiedApp } : undefined,
  };
}

/** Checks Apple's identity token with verification-service and says who it is. */
export async function appleSession(idToken: string, nonce: string, clientIP: string): Promise<AppleSessionResult> {
  if (isDevStandIn()) return { ok: false, message: "Sign in with Apple needs the verification service." };
  const { status, json } = await callWorker("/v1/web/apple/session", { idToken, nonce }, clientIP);
  if (status !== 200) return { ok: false, message: String(json.message ?? "Sign in with Apple didn't go through.") };
  const signedIn = json.signedIn as Record<string, unknown> | undefined;
  if (signedIn && typeof signedIn.userRecordName === "string" && typeof signedIn.email === "string") {
    return {
      ok: true,
      signedIn: {
        email: signedIn.email,
        schoolID: String(signedIn.schoolID ?? ""),
        schoolName: String(signedIn.schoolName ?? ""),
        domainKind: String(signedIn.domainKind ?? "student"),
        userRecordName: signedIn.userRecordName,
      },
    };
  }
  const reason = json.reason === "verify" || json.reason === "confirm" ? json.reason : "new";
  if (typeof json.appleTicket !== "string") return { ok: false, message: "Sign in with Apple didn't go through." };
  return { ok: true, appleTicket: json.appleTicket, reason };
}

/**
 * Creates the Nexus account for a signed-in email that has none: verification-service
 * writes its CloudKit UserProfile and links the email to it. Returns its userRecordName.
 */
export async function createAccount(accountToken: string, details: AccountDetails, clientIP: string, appleTicket?: string): Promise<CreateAccountResult> {
  if (isDevStandIn()) {
    return { ok: false, message: "Creating accounts needs the verification service. Set VERIFICATION_URL in .env.local." };
  }
  const { status, json } = await callWorker("/v1/web/account/create", { accountToken, ...details, ...(appleTicket ? { appleTicket } : {}) }, clientIP);
  if (status === 200 && typeof json.userRecordName === "string") return { ok: true, userRecordName: json.userRecordName };
  return {
    ok: false,
    message: String(json.message ?? "Couldn't create your account. Try again."),
    signInAgain: status === 401,
  };
}

// MARK: - Development stand-in

type DevPending = { email: string; code: string; expiresAt: number; attempts: number; guest: boolean };
const devStore = ((globalThis as { __nexusDevCodes?: Map<string, DevPending> }).__nexusDevCodes ??= new Map());

function devRequest(email: string, purpose?: "guest"): RequestResult {
  const normalized = email.trim().toLowerCase();
  const guest = purpose === "guest";
  if (guest && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    return { ok: false, message: "That doesn't look like an email address." };
  }
  if (!guest && !/^[^\s@]+@[^\s@]+\.edu$/.test(normalized)) {
    return { ok: false, message: "Use your school (.edu) email address." };
  }
  const pendingID = randomUUID();
  const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
  devStore.set(pendingID, { email: normalized, code, expiresAt: Date.now() + 600_000, attempts: 0, guest });
  console.log(`\n[nexus dev] ${guest ? "Guest" : "Sign-in"} code for ${normalized}: ${code}\n`);
  return { ok: true, pendingID, schoolName: "your school" };
}

function devConfirm(pendingID: string, code: string): ConfirmResult {
  const pending = devStore.get(pendingID);
  if (!pending || pending.expiresAt < Date.now()) return { ok: false, message: "That code expired. Request a new one." };
  if (++pending.attempts > 5) return { ok: false, message: "Too many wrong codes. Request a new one." };
  if (pending.code !== code) return { ok: false, message: "That code isn't valid." };
  devStore.delete(pendingID);
  if (pending.guest) return { ok: true, email: pending.email, schoolID: "", schoolName: "", domainKind: "guest" };
  return { ok: true, email: pending.email, schoolID: "dev", schoolName: "Development", domainKind: "student", accountToken: "dev" };
}
