import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import AuthShell, { field, labelCls, primaryBtn } from "@/components/AuthShell";
import { currentSession } from "@/lib/account";
import { approveTVAction } from "./actions";

export const metadata: Metadata = { title: "Sign in to Apple TV · Nexus" };

type SearchParams = Promise<{ [key: string]: string | string[] | undefined }>;

/**
 * Where the QR code on the Apple TV app's sign-in screen points. On an iPhone with Nexus
 * installed the link opens the app instead (a universal link); everyone else lands here and
 * approves the TV as the account they're signed in to on the website.
 */
export default function TVSignIn({ searchParams }: { searchParams: SearchParams }) {
  return (
    // Reads the session cookie and the URL, so it renders at request time inside Suspense.
    <Suspense fallback={<AuthShell title="Sign in to Apple TV"><p className="text-sm text-white/65">One moment…</p></AuthShell>}>
      <TVSignInBody searchParams={searchParams} />
    </Suspense>
  );
}

async function TVSignInBody({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const code = typeof params.code === "string" ? params.code : "";
  const error = typeof params.error === "string" ? params.error : "";

  if (params.approved) {
    return (
      <AuthShell title="Your Apple TV is signed in" subtitle="Pick something to watch on your TV.">
        <Link href="/" className="text-sm text-white/70 underline underline-offset-4 hover:text-white">Back to Nexus</Link>
      </AuthShell>
    );
  }

  const session = await currentSession();
  if (!session) {
    return (
      <AuthShell title="Sign in to Apple TV" subtitle="Sign in to Nexus here first, then scan the code on your TV again.">
        <Link href="/signin" className={`${primaryBtn} flex items-center justify-center`}>Sign in</Link>
      </AuthShell>
    );
  }
  if (!session.userRecordName) {
    return (
      <AuthShell title="Sign in to Apple TV" subtitle="Finish creating your Nexus account first, then scan the code on your TV again.">
        <Link href="/" className={`${primaryBtn} flex items-center justify-center`}>Continue</Link>
      </AuthShell>
    );
  }

  return (
    <AuthShell title="Sign in to Apple TV" subtitle={`Your TV will watch as ${session.email}.`}>
      <form action={approveTVAction} className="space-y-4">
        <div>
          <label htmlFor="code" className={labelCls}>Code on your TV</label>
          <input
            id="code"
            name="code"
            defaultValue={code}
            required
            autoCapitalize="characters"
            autoComplete="off"
            placeholder="ABCD-EFGH"
            className={`${field} font-mono tracking-widest uppercase`}
          />
        </div>
        {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
        <button type="submit" className={primaryBtn}>Sign In Apple TV</button>
      </form>
    </AuthShell>
  );
}
