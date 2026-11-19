import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { threadsFor } from "@/lib/cloudkit/messages";

// GET /api/network/pulse
// A short fingerprint of the visitor's conversations (newest message, time and unread
// count of each, and each group photo's checksum). The open Network page asks for it every few seconds and only rebuilds
// itself when the fingerprint changes, instead of rebuilding every time.
// API routes skip the sign-in proxy, so this checks the session itself.
export async function GET() {
  const current = await currentAccount();
  const me = current?.session.userRecordName;
  if (!me || !isCloudKitConfigured()) return NextResponse.json({ pulse: null }, { status: current ? 200 : 401 });
  try {
    const threads = await threadsFor(me);
    const pulse = createHash("sha1").update(JSON.stringify(threads.map((t) => ({ ...t, groupPhotoUrl: undefined })))).digest("base64url");
    return NextResponse.json({ pulse }, { headers: { "cache-control": "no-store" } });
  } catch {
    return NextResponse.json({ pulse: null }, { status: 502 });
  }
}
