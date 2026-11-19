"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, useTransition, type FormEvent } from "react";
import { requestCodeAction } from "@/app/auth/actions";
import { primaryBtn } from "@/components/AuthShell";
import { useAuthSchool } from "@/components/AuthTheme";
import CodeStep from "@/components/CodeStep";
import SignedIn from "@/components/SignedIn";
import SchoolEmailBox from "@/components/SchoolEmailBox";
import SchoolPicker from "@/components/SchoolPicker";
import { emailDomains, isSchoolEmail, type SignupSchool } from "@/lib/signupSchools";

/**
 * Sign-in: pick your school (black and white screen, each school in its own colors),
 * then your email at that school and the 6-digit code, in the school's colors.
 * `mock` is the Mock launch walkthrough: no email is sent, any 6-digit code passes, and
 * nobody is signed in.
 */
export default function SignInForm({ mock = false }: { mock?: boolean }) {
  const router = useRouter();
  const [school, setSchool] = useState<SignupSchool | null>(null);
  // Only the part before "@" is typed: the school decides the rest.
  const [emailID, setEmailID] = useState("");
  const [pickedDomain, setPickedDomain] = useState("");
  const [pendingID, setPendingID] = useState<string | null>(null);
  const [mockDone, setMockDone] = useState(false);
  // After Sign in with Apple: this email also verified the person's app account.
  const [verifiedApp, setVerifiedApp] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();
  const themeSchool = useAuthSchool();
  useEffect(() => themeSchool(school), [themeSchool, school]);

  // Students and educators both sign in here, so every domain of the school is offered.
  const domains = school ? emailDomains(school) : [];
  const domain = domains.includes(pickedDomain) ? pickedDomain : domains[0] ?? "";
  const email = emailID && domain ? `${emailID}@${domain}` : "";
  const valid = !!school && isSchoolEmail(email, school) && !busy;

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid || !school) return;
    setError(null);
    if (mock) return setPendingID("mock");
    startTransition(async () => {
      const result = await requestCodeAction(email, school.id);
      if (result.ok) setPendingID(result.pendingID);
      else setError(result.message);
    });
  }

  if (!school) return <SchoolPicker onPick={setSchool} />;

  if (verifiedApp) {
    return <SignedIn heading="You're in!" note="Your school email is verified in the Nexus app too, and Sign in with Apple now works on both." />;
  }

  if (mockDone) {
    return <SignedIn heading="Welcome back!" note="That was the mock launch: nobody was signed in." />;
  }

  if (pendingID) {
    return (
      <CodeStep
        mock={mock}
        email={email}
        pendingID={pendingID}
        onBack={() => setPendingID(null)}
        // No account owns this email yet: finish sign-up to create one.
        onVerified={(hasAccount, outcome) => {
          if (mock) return setMockDone(true);
          if ((outcome as { verifiedApp?: boolean } | undefined)?.verifiedApp) return setVerifiedApp(true);
          router.replace(hasAccount ? "/" : "/signup/finish");
        }}
      />
    );
  }

  return (
    <form onSubmit={submit} className="space-y-4">
      <SchoolEmailBox school={school} domains={domains} id={emailID} onID={setEmailID} domain={domain} onDomain={setPickedDomain} />
      {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
      <button type="submit" disabled={!valid} className={primaryBtn}>
        {busy ? "Sending…" : "Send code"}
      </button>
      <button
        type="button"
        onClick={() => {
          setSchool(null);
          setError(null);
        }}
        className="w-full text-sm text-white/60 hover:text-white"
      >
        Back
      </button>
    </form>
  );
}
