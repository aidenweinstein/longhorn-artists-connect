"use client";

import { useEffect, useState, useTransition, type FormEvent } from "react";
import Link from "next/link";
import { createAccountAction, requestCodeAction } from "@/app/auth/actions";
import { ROLE_TAGS } from "@/lib/profileFields";
import { preparePhoto } from "@/lib/preparePhoto";
import { emailDomains, exampleName, isSchoolEmail, signupSchool, type SignupRole, type SignupSchool } from "@/lib/signupSchools";
import { field, labelCls, primaryBtn } from "@/components/AuthShell";
import { useAuthSchool } from "@/components/AuthTheme";
import CodeStep from "@/components/CodeStep";
import SchoolEmailBox from "@/components/SchoolEmailBox";
import SchoolPicker from "@/components/SchoolPicker";
import SignedIn from "@/components/SignedIn";

type Role = SignupRole;
type Step = "school" | "role" | "details" | "code" | "profile" | "done";

const ROLES: { id: Role; title: string }[] = [
  { id: "student", title: "I'm a Student" },
  { id: "educator", title: "I'm an Educator" },
];

const STEPS: Step[] = ["school", "role", "profile", "details", "code"];

/**
 * Sign-up. The school comes first, on a black and white screen with each school in its
 * own colors; picking one turns the rest of sign-up that school's colors. A profile
 * picture (required), name, major, class and tags come next, and the email and code come last: the right code creates the
 * account in that same request, so there's no gap for the sign-in to go missing in.
 * `finish` picks up after the email code for someone who signed in with an email that
 * has no account yet (`schoolID` is the school they signed in at), so it asks student or
 * educator and skips the school, email and code steps.
 * `mock` is the Mock launch walkthrough: every screen works, but no email is sent, any
 * 6-digit code passes, and no account or session is created.
 */
export default function SignUpForm({ finish = false, mock = false, schoolID, recheckEmail }: {
  finish?: boolean;
  mock?: boolean;
  schoolID?: string;
  /** Finish: this signed-in email has no account token, so it's sent a new code after the details. */
  recheckEmail?: string;
}) {
  const [step, setStep] = useState<Step>(finish ? "role" : "school");
  const [role, setRole] = useState<Role | null>(null);
  const [school, setSchool] = useState<SignupSchool | null>(() => (finish ? signupSchool(schoolID) ?? null : null));
  const themeSchool = useAuthSchool();
  // The screen is in the picked school's colors on every step but the school list.
  useEffect(() => themeSchool(step === "school" ? null : school), [themeSchool, step, school]);
  // The example in the name box: a well-known name from the school picked, or none.
  const [nameExample, setNameExample] = useState("");
  const [name, setName] = useState("");
  // Only the part before "@" is typed: the school and role decide the rest.
  const [emailID, setEmailID] = useState("");
  const [pickedDomain, setPickedDomain] = useState("");
  const [major, setMajor] = useState("");
  const [classOf, setClassOf] = useState("");
  const [pendingID, setPendingID] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  // Required: no account is made without a profile picture. Resized to a JPEG here.
  const [photo, setPhoto] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const [photoError, setPhotoError] = useState<string | null>(null);
  useEffect(() => () => {
    if (photoPreview) URL.revokeObjectURL(photoPreview);
  }, [photoPreview]);
  const [error, setError] = useState<string | null>(null);
  const [signInAgain, setSignInAgain] = useState(false);
  // The code was right but creating the account failed: Create account retries it.
  const [codeDone, setCodeDone] = useState(false);
  const [existing, setExisting] = useState(false);
  const [busy, startTransition] = useTransition();
  // TESTING ONLY (`npm run dev`): the email and code steps were skipped, so the rest of the
  // steps can be seen. With no verified email there is nothing to make an account from, so
  // the last step ends like the mock walkthrough: no account, no session.
  const [skipped, setSkipped] = useState(false);
  const practice = mock || skipped;

  const student = role === "student";
  // Everyone verifies with an address at the school they picked: students its student
  // domain, educators one of its educator domains.
  const domains = school && role ? emailDomains(school, role) : [];
  const domain = domains.includes(pickedDomain) ? pickedDomain : domains[0] ?? "";
  const email = recheckEmail ?? (emailID && domain ? `${emailID}@${domain}` : "");
  const emailOk = !!school && !!role && isSchoolEmail(email, school, role);
  const [firstName, ...rest] = name.trim().split(/\s+/);
  const lastName = rest.join(" ");

  function verified(hasAccount: boolean, outcome?: { created?: boolean; createError?: string; signInAgain?: boolean }) {
    // This email already has a Nexus account (made in the app or here): they're signed in.
    if (hasAccount) {
      setExisting(true);
      return setStep("done");
    }
    if (practice || outcome?.created) return setStep("done");
    // Verified, but the account wasn't made: back to the details, where Create account retries.
    setCodeDone(true);
    setError(outcome?.createError ?? "Something went wrong creating your account. Try again.");
    setSignInAgain(!!outcome?.signInAgain);
    startProfile();
  }

  function startProfile() {
    setStep("profile");
  }

  async function choosePhoto(file: File | undefined) {
    if (!file) return;
    setPhotoError(null);
    try {
      const ready = await preparePhoto(file, 1024, "profile.jpg");
      setPhoto(ready);
      setPhotoPreview(URL.createObjectURL(ready));
    } catch {
      setPhotoError("That photo couldn't be read. Try a JPEG or PNG.");
    }
  }

  const toggleTag = (tag: string) => setTags((on) => (on.includes(tag) ? on.filter((t) => t !== tag) : [...on, tag]));

  function submitDetails(e: FormEvent) {
    e.preventDefault();
    if (!emailOk || busy) return;
    setError(null);
    if (mock) return setStep("code");
    startTransition(async () => {
      const result = await requestCodeAction(email, school?.id, role ?? "student");
      if (result.ok) {
        setPendingID(result.pendingID);
        setStep("code");
      } else setError(result.message);
    });
  }

  function submitProfile(e: FormEvent) {
    e.preventDefault();
    if (!profileOk || busy) return;
    setError(null);
    setSignInAgain(false);
    // New sign-ups go on to the email and code; the account is made when the code is right.
    if (!finish && !codeDone) return setStep("details");
    // Finishing with an old sign-in: a fresh code to the same email, which makes the account.
    if (recheckEmail && !codeDone) {
      startTransition(async () => {
        const result = await requestCodeAction(recheckEmail, school?.id, role ?? "student");
        if (result.ok) {
          setPendingID(result.pendingID);
          setStep("code");
        } else setError(result.message);
      });
      return;
    }
    if (practice) return setStep("done");
    startTransition(async () => {
      const result = await createAccountAction({ firstName, lastName, major, classOf: student ? classOf : "", tags, role: role ?? "student", photo: photo ?? undefined });
      if (result.ok) setStep("done");
      else {
        setError(result.message);
        setSignInAgain(!!result.signInAgain);
      }
    });
  }

  const profileOk = !!photo && !!firstName && !!lastName && !!major.trim() && (!student || /^\d{4}$/.test(classOf));

  const progress = step === "done" ? STEPS.length : STEPS.indexOf(step) + 1;

  return (
    <div>
      <div className="mb-6 flex gap-1.5" aria-hidden>
        {STEPS.map((s, i) => (
          <span key={s} className={`h-1 flex-1 rounded-full ${i < progress ? "bg-[var(--auth-line)]" : "bg-white/15"}`} />
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
                role === r.id ? "border-[var(--auth-line)] bg-white/10" : "border-white/15 hover:border-white/30"
              }`}
            >
              <p className="font-semibold">{r.title}</p>
            </button>
          ))}
          <button type="button" disabled={!role} onClick={startProfile} className={`${primaryBtn} mt-3`}>
            Next
          </button>
          {!finish && (
            <button type="button" onClick={() => setStep("school")} className="w-full text-sm text-white/60 hover:text-white">Back</button>
          )}
        </div>
      )}

      {step === "school" && (
        <SchoolPicker
          onPick={(s) => {
            setSchool(s);
            setNameExample(exampleName(s));
            setStep("role");
          }}
        />
      )}

      {step === "details" && role && school && (
        <form onSubmit={submitDetails} className="space-y-4">
          <SchoolEmailBox school={school} domains={domains} id={emailID} onID={setEmailID} domain={domain} onDomain={setPickedDomain} />
          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
          <button type="submit" disabled={!emailOk || busy} className={primaryBtn}>
            {busy ? "Sending…" : "Send code"}
          </button>
          <button type="button" onClick={() => setStep("profile")} className="w-full text-sm text-white/60 hover:text-white">Back</button>
          {/* Testing shortcut; only under `npm run dev`, never on the live site. */}
          {process.env.NODE_ENV === "development" && !mock && (
            <button
              type="button"
              onClick={() => {
                setError(null);
                setSkipped(true);
                setStep("done");
              }}
              className="h-10 w-full rounded-full border border-dashed border-yellow-400/60 text-sm font-semibold text-yellow-300 transition hover:bg-yellow-300/10"
            >
              Skip email and code (testing only)
            </button>
          )}
        </form>
      )}

      {step === "code" && (
        <CodeStep
          mock={mock}
          email={email}
          pendingID={pendingID}
          onBack={() => setStep(recheckEmail ? "profile" : "details")}
          onVerified={verified}
          account={{ firstName, lastName, major, classOf: student ? classOf : "", tags, role: role ?? "student", photo: photo ?? undefined }}
        />
      )}

      {step === "profile" && (
        <form onSubmit={submitProfile} className="space-y-4">
          <div>
            <p className={labelCls}>Profile Picture</p>
            <div className="flex items-center gap-4">
              {photoPreview ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={photoPreview} alt="Your profile picture" className="h-20 w-20 shrink-0 rounded-full object-cover" />
              ) : (
                <span aria-hidden className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full border-2 border-dashed border-white/30 text-3xl text-white/40">
                  +
                </span>
              )}
              <div className="space-y-1">
                <label className="inline-block cursor-pointer rounded-full border border-white/25 px-4 py-2 text-sm font-semibold transition hover:bg-white/10 focus-within:ring-2 focus-within:ring-[var(--auth-line)]">
                  {photo ? "Change photo" : "Add photo"}
                  <input type="file" accept="image/jpeg,image/png,image/heic,image/*" className="sr-only" onChange={(e) => choosePhoto(e.target.files?.[0])} />
                </label>
                <p className="text-xs text-white/55">{photo ? "Looking good." : "Required. This is how people will recognize you on Nexus."}</p>
              </div>
            </div>
            {photoError && <p role="alert" className="mt-2 text-sm text-red-400">{photoError}</p>}
          </div>
          <div>
            <label htmlFor="name" className={labelCls}>First &amp; Last Name</label>
            <input id="name" autoComplete="name" value={name} onChange={(e) => setName(e.target.value)} className={field} placeholder={nameExample} autoFocus />
          </div>
          <div>
            <label htmlFor="major" className={labelCls}>{student ? "Major" : "Department"}</label>
            <input id="major" value={major} onChange={(e) => setMajor(e.target.value)} className={field} placeholder="Radio-Television-Film" />
          </div>
          {student && (
            <div>
              <label htmlFor="classOf" className={labelCls}>Class of</label>
              {/* Typed, not picked from a list: four digits, like Edit profile's graduation year. */}
              <input
                id="classOf"
                value={classOf}
                onChange={(e) => setClassOf(e.target.value.replace(/\D/g, "").slice(0, 4))}
                className={field}
                inputMode="numeric"
                autoComplete="off"
                maxLength={4}
                placeholder="2028"
              />
            </div>
          )}
          <div>
            <p className={labelCls}>Tags</p>
            <div className="flex flex-wrap gap-2">
              {ROLE_TAGS.map((tag) => {
                const on = tags.includes(tag);
                return (
                  <button
                    key={tag}
                    type="button"
                    aria-pressed={on}
                    onClick={() => toggleTag(tag)}
                    className={`rounded-full px-3 py-1.5 text-sm font-medium transition ${
                      on ? "bg-[var(--auth)] text-[var(--auth-fg)]" : "bg-white/10 text-white/80 hover:bg-white/20"
                    }`}
                  >
                    {tag}
                  </button>
                );
              })}
            </div>
          </div>
          {error && (
            <p role="alert" className="text-sm text-red-400">
              {error}{" "}
              {signInAgain && <Link href="/signin" className="font-semibold underline">Sign in</Link>}
            </p>
          )}
          <button type="submit" disabled={!profileOk || busy} className={primaryBtn}>
            {recheckEmail && !codeDone ? (busy ? "Sending code…" : "Next") : finish || codeDone ? (busy ? "Creating account…" : "Create account") : "Next"}
          </button>
          {!finish && !codeDone && (
            <button type="button" onClick={() => setStep("role")} className="w-full text-sm text-white/60 hover:text-white">Back</button>
          )}
        </form>
      )}

      {step === "done" && practice && (
        <div className="space-y-4 text-center">
          <p className="text-lg font-semibold">You&rsquo;re in, {firstName}!</p>
          <p className="text-sm text-white/65">
            Your Nexus account is ready. People on Nexus, including in the iPhone app, can now find your profile.
          </p>
          <Link href="/" className={`${primaryBtn} flex items-center justify-center`}>Go to Nexus</Link>
          {mock ? (
            <p className="text-xs text-white/50">
              That was the mock launch: no account was created.{" "}
              <Link href="/welcome/mock" className="font-semibold text-[var(--auth-line)] underline underline-offset-4 hover:opacity-80">Run it again</Link>
            </p>
          ) : (
            <p className="text-xs text-yellow-300/80">Testing: the email step was skipped, so no account was created and you are not signed in.</p>
          )}
        </div>
      )}

      {step === "done" && !practice && (
        <SignedIn
          heading={existing ? "Welcome back!" : `You're in, ${firstName}!`}
          note={
            existing
              ? "This email already has a Nexus account, so you're signed in to it."
              : "Your Nexus account is ready. People on Nexus, including in the iPhone app, can now find your profile."
          }
        />
      )}
    </div>
  );
}
