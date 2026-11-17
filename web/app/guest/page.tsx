import type { Metadata } from "next";
import Link from "next/link";
import AuthShell from "@/components/AuthShell";
import GuestForm from "./GuestForm";

export const metadata: Metadata = { title: "Continue as guest · Nexus" };

export default function Guest() {
  return (
    <AuthShell
      title="Continue as guest"
      subtitle="Enter any email address. We'll send a six-digit code to confirm it's yours."
      footer={
        <>
          Have a school email?{" "}
          <Link href="/signup" className="font-semibold text-brand hover:underline">Create an account</Link>
        </>
      }
    >
      <GuestForm />
    </AuthShell>
  );
}
