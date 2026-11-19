import type { Metadata } from "next";
import { Suspense } from "react";
import Link from "next/link";
import AppleSignIn from "@/components/AppleSignIn";
import AuthShell from "@/components/AuthShell";
import DevSkipSignIn from "@/components/DevSkipSignIn";
import SignInForm from "./SignInForm";

export const metadata: Metadata = { title: "Sign in · Nexus" };

export default function SignIn({ searchParams }: { searchParams: Promise<{ [key: string]: string | string[] | undefined }> }) {
  return (
    <AuthShell
      title="Sign in"
      subtitle="Use the same account as the Nexus app."
      footer={
        <>
          New to Nexus?{" "}
          <Link href="/signup" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Create an account</Link>
        </>
      }
    >
      {/* Sign in with Apple, or what the email step is for once Apple is done. Reads cookies, so request time only. */}
      <Suspense fallback={null}>
        <AppleSignIn searchParams={searchParams} />
      </Suspense>
      <SignInForm />
      {/* Testing shortcut; renders nothing outside `npm run dev`. */}
      <DevSkipSignIn />
    </AuthShell>
  );
}
