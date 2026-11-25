"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { currentSession } from "@/lib/account";
import { approveTV } from "@/lib/verification";

async function clientIP(): Promise<string> {
  const h = await headers();
  return h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "unknown";
}

/** Signs the Apple TV showing `code` in as whoever is signed in here. */
export async function approveTVAction(formData: FormData) {
  const code = String(formData.get("code") ?? "").toUpperCase().replace(/[\s-]/g, "");
  const session = await currentSession();
  if (!session?.userRecordName) redirect(`/tv?code=${encodeURIComponent(code)}`);

  const result = await approveTV(code, session.userRecordName, await clientIP());
  if (!result.ok) redirect(`/tv?code=${encodeURIComponent(code)}&error=${encodeURIComponent(result.message)}`);
  redirect("/tv?approved=1");
}
