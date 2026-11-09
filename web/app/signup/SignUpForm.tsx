"use client";

import { useState, useTransition, type FormEvent } from "react";
import { requestCodeAction } from "@/app/auth/actions";
import { chooseStyle } from "@/app/(app)/portfolio/style/actions";
import { PROFILE_STYLES, STYLE_INFO, type ProfileStyle } from "@/lib/profileStyle";
import { field, labelCls, primaryBtn } from "@/components/AuthShell";
import CodeStep from "@/components/CodeStep";
import NotConnected from "@/components/NotConnected";
import SignedIn from "@/components/SignedIn";

type Role = "student" | "professional";
type Step = "role" | "details" | "code" | "style" | "profile" | "done";

const ROLES: { id: Role; title: string; body: string }[] = [
  { id: "student", title: "I'm a Student", body: "Share your work and get discovered. Verify with your school email." },
  { id: "professional", title: "I'm an Industry Professional", body: "Find student talent and connect with emerging creatives." },
];

const STEPS: Step[] = ["role", "details", "code", "style", "profile"];

export default function SignUpForm() {
  const [step, setStep] = useState<Step>("role");
  const [role, setRole] = useState<Role | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [major, setMajor] = useState("");
  const [classOf, setClassOf] = useState("");
  const [pendingID, setPendingID] = useState("");
  const [style, setStyle] = useState<ProfileStyle | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, startTransition] = useTransition();

  const student = role === "student";
  const emailOk = /\S+@\S+\.\S+/.test(email.trim()) && (!student || /\.edu$/i.test(email.trim()));
  const detailsOk = name.trim().split(/\s+/).length >= 2 && emailOk;
  const [years, setYears] = useState<number[]>([]);

  function verified() {
    if (!student) return setStep("done");
    const now = new Date().getFullYear();
    setYears(Array.from({ length: 6 }, (_, i) => now + i));
    setStep("style");
  }

  /** Every student account picks a base profile style before it's created. */
  function submitStyle() {
    if (!style || busy) return;
    setError(null);
    startTransition(async () => {
      const result = await chooseStyle(style);
      if (result.ok) setStep("profile");
      else setError(result.message);
    });
  }

  function submitDetails(e: FormEvent) {
    e.preventDefault();
    if (!detailsOk || busy) return;
    setError(null);
    startTransition(async () => {
      const result = await requestCodeAction(email.trim());
      if (result.ok) {
        setPendingID(result.pendingID);
        setStep("code");
      } else setError(result.message);
    });
  }

  function submitProfile(e: FormEvent) {
    e.preventDefault();
    setStep("done");
  }

  const progress = step === "done" ? STEPS.length : STEPS.indexOf(step) + 1;

  return (
    <div>
      <div className="mb-6 flex gap-1.5" aria-hidden>
        {STEPS.map((s, i) => (
          <span key={s} className={`h-1 flex-1 rounded-full ${i < progress ? "bg-brand" : "bg-white/15"}`} />
        ))}
      </div>

      {step === "role" && (
        <div className="space-y-3">
          {ROLES.map((r) => (
            <button
              key={r.id}
              type="button"
              onClick={() => setRole(r.id)}
              aria-pressed={role === r.id}
              className={`w-full rounded-2xl border p-4 text-left transition ${
                role === r.id ? "border-brand bg-brand/15" : "border-white/15 hover:border-white/30"
              }`}
            >
              <p className="font-semibold">{r.title}</p>
              <p className="mt-1 text-sm text-white/65">{r.body}</p>
            </button>
          ))}
          <button type="button" disabled={!role} onClick={() => setStep("details")} className={`${primaryBtn} mt-3`}>
            Next
          </button>
        </div>
      )}

      {step === "details" && !student && (
        <div className="space-y-4">
          <NotConnected
            heading="Industry accounts are app-only for now"
            body="Web sign-up currently verifies school email addresses only. Create your professional account in the Nexus app, or browse the website as a guest."
          />
          <button type="button" onClick={() => setStep("role")} className="w-full text-sm text-white/60 hover:text-white">Back</button>
        </div>
      )}

      {step === "details" && student && (
        <form onSubmit={submitDetails} className="space-y-4">
          <div>
            <label htmlFor="name" className={labelCls}>First &amp; Last Name</label>
            <input id="name" autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} className={field} placeholder="Jane Doe" />
          </div>
          <div>
            <label htmlFor="email" className={labelCls}>{student ? "School email" : "Work email"}</label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={field}
              placeholder={student ? "you@school.edu" : "you@company.com"}
            />
            {student && email.includes("@") && !/\.edu$/i.test(email.trim()) && (
              <p className="mt-1.5 text-xs text-white/55">Use your .edu email so we can verify your school.</p>
            )}
          </div>
          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
          <button type="submit" disabled={!detailsOk || busy} className={primaryBtn}>
            {busy ? "Sending…" : "Send code"}
          </button>
          <button type="button" onClick={() => setStep("role")} className="w-full text-sm text-white/60 hover:text-white">Back</button>
        </form>
      )}

      {step === "code" && (
        <CodeStep email={email.trim()} pendingID={pendingID} onBack={() => setStep("details")} onVerified={verified} />
      )}

      {step === "style" && (
        <div className="space-y-3">
          <div>
            <p className="font-semibold">I&rsquo;m a&hellip;</p>
            <p className="mt-1 text-sm text-white/65">
              Your base profile decides what Nexus recommends to you and how your profile looks. You can change it later.
            </p>
          </div>
          {PROFILE_STYLES.map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setStyle(s)}
              aria-pressed={style === s}
              className={`w-full rounded-2xl border p-4 text-left transition ${
                style === s ? "border-brand bg-brand/15" : "border-white/15 hover:border-white/30"
              }`}
            >
              <p className="font-semibold">
                {s} <span className="ml-1 text-xs font-normal text-white/55">{STYLE_INFO[s].looksLike}</span>
              </p>
              <p className="mt-1 text-sm text-white/65">{STYLE_INFO[s].pitch}</p>
            </button>
          ))}
          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
          <button type="button" disabled={!style || busy} onClick={submitStyle} className={`${primaryBtn} mt-3`}>
            {busy ? "Saving…" : "Next"}
          </button>
        </div>
      )}

      {step === "profile" && (
        <form onSubmit={submitProfile} className="space-y-4">
          <div>
            <label htmlFor="major" className={labelCls}>Major</label>
            <input id="major" value={major} onChange={(e) => setMajor(e.target.value)} className={field} placeholder="Radio-Television-Film" />
          </div>
          <div>
            <label htmlFor="classOf" className={labelCls}>Class of</label>
            <select id="classOf" value={classOf} onChange={(e) => setClassOf(e.target.value)} className={field}>
              <option value="">Select year</option>
              {years.map((y) => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>
          </div>
          <button type="submit" disabled={!major.trim() || !classOf} className={primaryBtn}>Create account</button>
        </form>
      )}

      {step === "done" && (
        <SignedIn
          heading={`You're in, ${name.trim().split(/\s+/)[0]}!`}
          note="Your email is verified. Profile details will be saved once website accounts connect to the app."
        />
      )}
    </div>
  );
}
