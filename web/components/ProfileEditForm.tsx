"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, useTransition, type ReactNode } from "react";
import { saveProfile } from "@/app/(app)/portfolio/edit/actions";
import { ROLE_TAGS, type ProfileFields } from "@/lib/profileFields";
import { WORK_STATUSES, parseWorkStatus, workStatusValue, type WorkStatusKind } from "@/lib/workStatus";
import Avatar from "./Avatar";

const field = "w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-brand";

/** Shrinks a chosen photo to at most 1024px and re-encodes it as JPEG, so uploads stay small. */
async function preparePhoto(file: File): Promise<File> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1024 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
  if (!blob) throw new Error("Couldn't read that photo.");
  return new File([blob], "profile.jpg", { type: "image/jpeg" });
}

function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium">
        {label} {hint && <span className="font-normal text-muted">{hint}</span>}
      </span>
      {children}
    </label>
  );
}

export default function ProfileEditForm({ initial, imageUrl, school }: { initial: ProfileFields; imageUrl?: string; school: string }) {
  const router = useRouter();
  const [p, setP] = useState(initial);
  const [photo, setPhoto] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = <K extends keyof ProfileFields>(key: K, value: ProfileFields[K]) => setP((cur) => ({ ...cur, [key]: value }));

  // Free the preview's memory when it's replaced or the page closes.
  useEffect(() => () => {
    if (preview) URL.revokeObjectURL(preview);
  }, [preview]);

  async function choosePhoto(file: File | undefined) {
    if (!file) return;
    setError(null);
    try {
      const ready = await preparePhoto(file);
      setPhoto(ready);
      setPreview(URL.createObjectURL(ready));
    } catch {
      setError("That photo couldn't be read. Try a JPEG or PNG.");
    }
  }

  const status = parseWorkStatus(p.workStatus);
  // Today in Austin, as the date picker's earliest choice.
  const [today] = useState(() => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Chicago" }).format(new Date()));

  /** Booked starts two weeks out; the date can be changed beside it. */
  function chooseStatus(kind: WorkStatusKind | null) {
    if (kind === null) return set("workStatus", "");
    if (kind !== "Booked") return set("workStatus", workStatusValue(kind));
    if (status?.kind === "Booked") return;
    const inTwoWeeks = new Date(Date.parse(`${today}T12:00:00Z`) + 14 * 864e5).toISOString().slice(0, 10);
    set("workStatus", workStatusValue("Booked", inTwoWeeks));
  }

  function toggleRole(role: string) {
    set("roles", p.roles.includes(role) ? p.roles.filter((r) => r !== role) : [...p.roles, role]);
  }

  function submit() {
    setError(null);
    const form = new FormData();
    for (const [key, value] of Object.entries(p)) {
      if (key === "roles") (value as string[]).forEach((r) => form.append("roles", r));
      else form.set(key, String(value));
    }
    if (photo) form.set("photo", photo);
    start(async () => {
      const res = await saveProfile(form);
      if (!res.ok) return setError(res.message);
      router.push("/portfolio");
      router.refresh();
    });
  }

  const name = `${p.firstName} ${p.lastName}`.trim();

  return (
    <form
      className="mx-auto max-w-2xl space-y-8 pb-16"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <header className="flex items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">Edit profile</h1>
        <Link href="/portfolio" className="text-sm text-muted hover:text-foreground">
          Cancel
        </Link>
      </header>

      <section className="flex items-center gap-5">
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={preview} alt="" className="h-28 w-28 shrink-0 rounded-full object-cover" />
        ) : (
          <Avatar name={name || "?"} src={imageUrl} size="xl" />
        )}
        <label className="cursor-pointer rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-surface">
          {imageUrl || preview ? "Change photo" : "Add photo"}
          <input type="file" accept="image/jpeg,image/png,image/heic,image/*" className="sr-only" onChange={(e) => choosePhoto(e.target.files?.[0])} />
        </label>
      </section>

      <section className="grid gap-4 sm:grid-cols-2">
        <Field label="First name">
          <input className={field} value={p.firstName} maxLength={60} onChange={(e) => set("firstName", e.target.value)} />
        </Field>
        <Field label="Last name">
          <input className={field} value={p.lastName} maxLength={60} onChange={(e) => set("lastName", e.target.value)} />
        </Field>
      </section>

      <Field label="Bio">
        <textarea
          className={field}
          rows={4}
          maxLength={1000}
          value={p.bio}
          placeholder="Introduce yourself and your work."
          onChange={(e) => set("bio", e.target.value)}
        />
      </Field>

      <section>
        <p className="mb-2 text-sm font-medium">Status</p>
        <div className="flex flex-wrap items-center gap-2">
          {([null, ...WORK_STATUSES.map((s) => s.kind)] as (WorkStatusKind | null)[]).map((kind) => {
            const on = (status?.kind ?? null) === kind;
            return (
              <button
                key={kind ?? "none"}
                type="button"
                aria-pressed={on}
                onClick={() => chooseStatus(kind)}
                className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                  on ? "bg-brand text-white" : "bg-foreground/10 text-foreground/80 hover:bg-foreground/20"
                }`}
              >
                {kind === null ? "None" : kind === "Booked" ? "Booked until…" : kind}
              </button>
            );
          })}
          {status?.kind === "Booked" && (
            <input
              type="date"
              aria-label="Booked until"
              value={status.until ?? ""}
              min={today}
              onChange={(e) => e.target.value && set("workStatus", workStatusValue("Booked", e.target.value))}
              className="rounded-xl border border-border bg-background px-3 py-1.5 text-sm outline-none focus:border-brand"
            />
          )}
        </div>
        <p className="mt-1.5 text-xs text-muted">Shown on your card on the People pages and on your profile.</p>
      </section>

      <section>
        <p className="mb-2 text-sm font-medium">Roles</p>
        <div className="flex flex-wrap gap-2">
          {ROLE_TAGS.map((role) => {
            const on = p.roles.includes(role);
            return (
              <button
                key={role}
                type="button"
                aria-pressed={on}
                onClick={() => toggleRole(role)}
                className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                  on ? "bg-brand text-white" : "bg-foreground/10 text-foreground/80 hover:bg-foreground/20"
                }`}
              >
                {role}
              </button>
            );
          })}
        </div>
      </section>

      <section className="space-y-4">
        <label className="flex items-center gap-3 text-sm font-medium">
          <input
            type="checkbox"
            checked={p.isIndustryProfessional}
            onChange={(e) => set("isIndustryProfessional", e.target.checked)}
            className="h-4 w-4 accent-[var(--brand)]"
          />
          I&rsquo;m an industry professional
        </label>

        {p.isIndustryProfessional ? (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Role">
              <input className={field} value={p.companyRole} maxLength={80} placeholder="Producer" onChange={(e) => set("companyRole", e.target.value)} />
            </Field>
            <Field label="Company">
              <input className={field} value={p.company} maxLength={80} onChange={(e) => set("company", e.target.value)} />
            </Field>
            <Field label="Industry">
              <input className={field} value={p.industry} maxLength={80} placeholder="Film & TV" onChange={(e) => set("industry", e.target.value)} />
            </Field>
          </div>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Major">
              <input className={field} value={p.major} maxLength={80} onChange={(e) => set("major", e.target.value)} />
            </Field>
            <Field label="Graduation year">
              <input
                className={field}
                value={p.graduationYear}
                inputMode="numeric"
                maxLength={4}
                placeholder="2027"
                onChange={(e) => set("graduationYear", e.target.value.replace(/\D/g, ""))}
              />
            </Field>
            <Field label="Minor" hint="(optional)">
              <input className={field} value={p.minor} maxLength={80} onChange={(e) => set("minor", e.target.value)} />
            </Field>
            <Field label="Certificate" hint="(optional)">
              <input className={field} value={p.certificate} maxLength={80} onChange={(e) => set("certificate", e.target.value)} />
            </Field>
          </div>
        )}
        {school && <p className="text-sm text-muted">School: {school}. It comes from your verified email, so it can&rsquo;t be changed here.</p>}
      </section>

      <section className="grid gap-4 sm:grid-cols-2">
        <Field label="Instagram" hint="(optional)">
          <div className="flex items-center rounded-xl border border-border bg-background focus-within:border-brand">
            <span className="pl-3 text-sm text-muted">@</span>
            <input
              className="w-full bg-transparent px-1 py-2.5 text-sm outline-none"
              value={p.instagramHandle.replace(/^@/, "")}
              maxLength={60}
              onChange={(e) => set("instagramHandle", e.target.value)}
            />
          </div>
        </Field>
        <Field label="Website" hint="(optional)">
          <input className={field} value={p.websiteURL} maxLength={300} placeholder="yourname.com" onChange={(e) => set("websiteURL", e.target.value)} />
        </Field>
      </section>

      {error && <p className="rounded-xl bg-red-500/10 p-3 text-sm text-red-500">{error}</p>}

      <div className="flex gap-3">
        <button
          type="submit"
          disabled={pending || !p.firstName.trim()}
          className="rounded-full bg-brand px-6 py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60"
        >
          {pending ? "Saving…" : "Save profile"}
        </button>
        <Link href="/portfolio" className="rounded-full border border-border px-6 py-2.5 text-sm font-semibold hover:bg-surface">
          Cancel
        </Link>
      </div>
    </form>
  );
}
