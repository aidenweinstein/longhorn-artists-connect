import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import SignUpForm from "./SignUpForm";

export const metadata: Metadata = { title: "Create account · Nexus" };

export default function SignUp() {
  return (
    <AuthShell
      title="Create Your Account"
      subtitle="Join student creatives and industry professionals on Nexus."
      footer={
        <>
          Already have an account?{" "}
          <Link href="/signin" className="font-semibold text-brand hover:underline">Sign in</Link>
        </>
      }
    >
      <SignUpForm />
    </AuthShell>
  );
}
