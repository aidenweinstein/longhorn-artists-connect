"use server";

import { cookies, headers } from "next/headers";
import { SESSION_COOKIE, SESSION_MAX_AGE, encodeSession } from "@/lib/session";
import { confirmCode, requestCode, type RequestResult } from "@/lib/verification";

async function clientIP(): Promise<string> {
  const h = await headers();
  return h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
}

export async function requestCodeAction(email: string): Promise<RequestResult> {
  return requestCode(email, await clientIP());
}

export async function confirmCodeAction(
  pendingID: string,
  code: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (!/^\d{6}$/.test(code)) return { ok: false, message: "Enter the 6-digit code." };

  const result = await confirmCode(pendingID, code, await clientIP());
  if (!result.ok) return result;

  const jar = await cookies();
  jar.set(SESSION_COOKIE, encodeSession({
    email: result.email,
    schoolID: result.schoolID,
    schoolName: result.schoolName,
    domainKind: result.domainKind,
    userRecordName: result.userRecordName,
    issuedAt: Math.floor(Date.now() / 1000),
  }), {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: SESSION_MAX_AGE,
  });
  return { ok: true };
}

export async function signOutAction(): Promise<void> {
  (await cookies()).delete(SESSION_COOKIE);
}
