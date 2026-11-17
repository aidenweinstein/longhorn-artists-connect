import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import SignUpForm from "./SignUpForm";

export const metadata: Metadata = { title: "Create account · Nexus" };

export default function SignUp() {
  return (
    <AuthShell
      title="Create Your Account"
      footer={
        <>
          Already have an account?{" "}
          <Link href="/signin" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Sign in</Link>
        </>
      }
    >
      <SignUpForm />
    </AuthShell>
  );
}
