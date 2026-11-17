import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import MockBanner from "@/components/MockBanner";
import SignInForm from "../SignInForm";

export const metadata: Metadata = { title: "Mock launch · Sign in · Nexus" };

/** Mock launch: every sign-in screen, with no email sent and nobody signed in. */
export default function MockSignIn() {
  return (
    <>
      <MockBanner className="fixed left-1/2 top-6 -translate-x-1/2 whitespace-nowrap" />
      <AuthShell
        title="Sign in"
        subtitle="Use the same account as the Nexus app."
        footer={
          <>
            New to Nexus?{" "}
            <Link href="/signup/mock" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Create an account</Link>
          </>
        }
      >
        <SignInForm mock />
      </AuthShell>
    </>
  );
}
