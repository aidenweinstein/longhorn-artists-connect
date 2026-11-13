import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
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
          <Link href="/signin" className="font-semibold text-brand hover:underline">Sign in again</Link>
        </>
      }
    >
      <SignUpForm finish />
    </AuthShell>
  );
}
