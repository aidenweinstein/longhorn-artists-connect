import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import DevSkipSignIn from "@/components/DevSkipSignIn";
import SignInForm from "./SignInForm";

export const metadata: Metadata = { title: "Sign in · Nexus" };

export default function SignIn() {
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
      <SignInForm />
      {/* Testing shortcut; renders nothing outside `npm run dev`. */}
      <DevSkipSignIn />
    </AuthShell>
  );
}
