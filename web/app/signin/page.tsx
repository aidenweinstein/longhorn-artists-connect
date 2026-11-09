import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
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
          <Link href="/signup" className="font-semibold text-brand hover:underline">Create an account</Link>
        </>
      }
    >
      <SignInForm />
    </AuthShell>
  );
}
