/** An alum waiting for a moderator, from verification-service (src/alumni.ts). */
export type PendingAlum = {
  userRecordName: string;
  schoolID: string;
  schoolName: string;
  /** The address they signed up with. */
  email: string;
  /** Seconds since 1970. */
  requestedAt: number;
};

/** verification-service's /v1/web/alumni/* routes. Server-only: uses WEB_CLIENT_TOKEN. */
export async function callAlumni<T>(path: "pending" | "decide", body: unknown): Promise<T> {
  const url = process.env.VERIFICATION_URL?.replace(/\/$/, "");
  const token = process.env.WEB_CLIENT_TOKEN;
  if (!url || !token) throw new Error("Alumni approval isn't set up on this server yet.");
  let res: Response;
  try {
    res = await fetch(`${url}/v1/web/alumni/${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
      cache: "no-store",
    });
  } catch {
    throw new Error("Couldn't reach the server. Try again.");
  }
  const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) throw new Error(String(json.message ?? "Something went wrong. Try again."));
  return json as T;
}
