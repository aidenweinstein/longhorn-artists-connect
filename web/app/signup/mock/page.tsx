import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import MockBanner from "@/components/MockBanner";
import SignUpForm from "../SignUpForm";

export const metadata: Metadata = { title: "Mock launch · Create account · Nexus" };

/** Mock launch: every sign-up screen, with no email sent and no account created. */
export default function MockSignUp() {
  return (
    <>
      <MockBanner className="fixed left-1/2 top-6 -translate-x-1/2 whitespace-nowrap" />
      <AuthShell
        title="Create Your Account"
        footer={
          <>
            Already have an account?{" "}
            <Link href="/signin/mock" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Sign in</Link>
          </>
        }
      >
        <SignUpForm mock />
      </AuthShell>
    </>
  );
}
