import type { Metadata } from "next";
import { Suspense } from "react";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import { currentSession } from "@/lib/account";
import SignUpForm from "../SignUpForm";

export const metadata: Metadata = { title: "Finish creating your account · Nexus" };

/** Where sign-in sends an email that has no Nexus account yet. */
export default function FinishSignUp() {
  return (
    <AuthShell
      title="Finish Creating Your Account"
      subtitle="Your email is verified. A few details and your Nexus account is ready."
      footer={
        <>
          Wrong email?{" "}
          <Link href="/signin" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Sign in again</Link>
        </>
      }
    >
      {/* The school they signed in at sets the colors; the session is only known at request time. */}
      <Suspense fallback={null}>
        <FinishForm />
      </Suspense>
    </AuthShell>
  );
}

async function FinishForm() {
  const session = await currentSession();
  // A sign-in from before website accounts worked (or whose token was lost) can't make an
  // account by itself: that email gets a fresh code at the end, which creates the account.
  const recheck = !!session && !session.userRecordName && !session.accountToken;
  return <SignUpForm finish schoolID={session?.schoolID} recheckEmail={recheck ? session.email : undefined} />;
}
