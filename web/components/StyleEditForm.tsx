"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, useTransition, type ReactNode } from "react";
import { saveStyle } from "@/app/(app)/portfolio/style/actions";
import {
  GENDERS,
  PROFILE_STYLES,
  RESUME_CATEGORIES,
  STYLE_INFO,
  UNIONS,
  type CreativeDetails,
  type ProfileStyle,
  type ResumeCredit,
} from "@/lib/profileStyle";

const field = "w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-brand";

/** Shrinks a headshot to at most 1400px on its long side and re-encodes it as JPEG. */
async function prepareHeadshot(file: File): Promise<File> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1400 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.88));
  if (!blob) throw new Error("Couldn't read that photo.");
  return new File([blob], "headshot.jpg", { type: "image/jpeg" });
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

function Section({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <section className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{title}</h2>
        {note && <p className="text-sm text-muted">{note}</p>}
      </div>
      {children}
    </section>
  );
}

export default function StyleEditForm({
  initialStyle,
  initial,
  headshotUrl,
  reels,
}: {
  initialStyle: ProfileStyle | null;
  initial: CreativeDetails;
  headshotUrl?: string;
  reels: { id: string; title: string; thumbnailUrl?: string }[];
}) {
  const router = useRouter();
  const [style, setStyle] = useState<ProfileStyle | null>(initialStyle);
  const [d, setD] = useState(initial);
  const [ageMin, setAgeMin] = useState(initial.actor.ageMin?.toString() ?? "");
  const [ageMax, setAgeMax] = useState(initial.actor.ageMax?.toString() ?? "");
  const [headshot, setHeadshot] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  useEffect(() => () => {
    if (preview) URL.revokeObjectURL(preview);
  }, [preview]);

  const setActor = <K extends keyof CreativeDetails["actor"]>(k: K, v: CreativeDetails["actor"][K]) =>
    setD((c) => ({ ...c, actor: { ...c.actor, [k]: v } }));
  const setMusician = <K extends keyof CreativeDetails["musician"]>(k: K, v: CreativeDetails["musician"][K]) =>
    setD((c) => ({ ...c, musician: { ...c.musician, [k]: v } }));
  const setFilmmaker = <K extends keyof CreativeDetails["filmmaker"]>(k: K, v: CreativeDetails["filmmaker"][K]) =>
    setD((c) => ({ ...c, filmmaker: { ...c.filmmaker, [k]: v } }));
  const setCredit = (i: number, patch: Partial<ResumeCredit>) =>
    setActor("resume", d.actor.resume.map((c, j) => (j === i ? { ...c, ...patch } : c)));

  async function chooseHeadshot(file: File | undefined) {
    if (!file) return;
    setError(null);
    try {
      const ready = await prepareHeadshot(file);
      setHeadshot(ready);
      setPreview(URL.createObjectURL(ready));
    } catch {
      setError("That photo couldn't be read. Try a JPEG or PNG.");
    }
  }

  function submit() {
    if (!style) return setError("Pick Filmmaker, Actor or Musician.");
    setError(null);
    const form = new FormData();
    form.set("style", style);
    const a = d.actor;
    form.set("ageMin", ageMin);
    form.set("ageMax", ageMax);
    for (const k of ["gender", "height", "ethnicAppearance", "hair", "eyes", "union", "basedIn", "languages", "specialSkills", "training"] as const) {
      form.set(k, a[k]);
    }
    form.set("reelPostID", a.reelPostID ?? "");
    for (const c of a.resume) {
      form.append("resumeID", c.id);
      form.append("resumeCategory", c.category);
      form.append("resumeProject", c.project);
      form.append("resumeRole", c.role);
      form.append("resumeCompany", c.company);
      form.append("resumeYear", c.year);
    }
    const m = d.musician;
    form.set("artistName", m.artistName);
    form.set("instruments", m.instruments);
    form.set("genres", m.genres);
    if (m.availableForGigs) form.set("availableForGigs", "on");
    if (m.availableForSessions) form.set("availableForSessions", "on");
    if (m.availableForScoring) form.set("availableForScoring", "on");
    form.set("specialties", d.filmmaker.specialties);
    form.set("gear", d.filmmaker.gear);
    if (d.filmmaker.openToCrew) form.set("openToCrew", "on");
    if (headshot) form.set("headshot", headshot);

    start(async () => {
      const res = await saveStyle(form);
      if (!res.ok) return setError(res.message);
      router.push("/portfolio");
      router.refresh();
    });
  }

  const shownHeadshot = preview ?? headshotUrl;

  return (
    <form
      className="mx-auto max-w-2xl space-y-10 pb-16"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <header className="flex items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">Profile style</h1>
        <Link href="/portfolio" className="text-sm text-muted hover:text-foreground">
          Cancel
        </Link>
      </header>

      <Section
        title="Base profile"
        note="Decides what Nexus recommends to you, what Now shows, and how your profile looks. A moderator reviews your profile before it's listed on the public page."
      >
        <div className="grid gap-3 sm:grid-cols-3">
          {PROFILE_STYLES.map((s) => (
            <button
              key={s}
              type="button"
              aria-pressed={style === s}
              onClick={() => setStyle(s)}
              className={`rounded-2xl border p-4 text-left transition ${style === s ? "border-brand bg-brand/10" : "border-border hover:bg-surface"}`}
            >
              <p className="font-semibold">{s}</p>
              <p className="text-xs text-brand">{STYLE_INFO[s].looksLike}</p>
              <p className="mt-1.5 text-xs text-muted">{STYLE_INFO[s].pitch}</p>
            </button>
          ))}
        </div>
      </Section>

      {style === "Actor" && (
        <>
          <Section title="Headshot">
            <div className="flex items-center gap-5">
              {shownHeadshot ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={shownHeadshot} alt="" className="h-40 w-[7.5rem] shrink-0 rounded-lg object-cover" />
              ) : (
                <span className="flex h-40 w-[7.5rem] shrink-0 items-center justify-center rounded-lg bg-surface text-xs text-muted">No headshot</span>
              )}
              <label className="cursor-pointer rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-surface">
                {shownHeadshot ? "Change headshot" : "Add headshot"}
                <input type="file" accept="image/jpeg,image/png,image/*" className="sr-only" onChange={(e) => chooseHeadshot(e.target.files?.[0])} />
              </label>
            </div>
          </Section>

          <Section title="Reel" note={reels.length ? "A Performance or Film you're credited on." : "Post a Performance or Film you're credited on in the app to use it as your reel."}>
            <select className={field} value={d.actor.reelPostID ?? ""} onChange={(e) => setActor("reelPostID", e.target.value || undefined)}>
              <option value="">None</option>
              {reels.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.title}
                </option>
              ))}
            </select>
          </Section>

          <Section title="Details" note="Age, gender, look and skills decide which open roles show up for you on Now.">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Playable age">
                <div className="flex items-center gap-2">
                  <input className={field} inputMode="numeric" placeholder="18" value={ageMin} onChange={(e) => setAgeMin(e.target.value.replace(/\D/g, "").slice(0, 2))} />
                  <span className="text-muted">–</span>
                  <input className={field} inputMode="numeric" placeholder="25" value={ageMax} onChange={(e) => setAgeMax(e.target.value.replace(/\D/g, "").slice(0, 2))} />
                </div>
              </Field>
              <Field label="Gender">
                <select className={field} value={d.actor.gender} onChange={(e) => setActor("gender", e.target.value)}>
                  <option value="">Not set</option>
                  {GENDERS.map((g) => (
                    <option key={g}>{g}</option>
                  ))}
                </select>
              </Field>
              <Field label="Height">
                <input className={field} maxLength={40} placeholder={`5'9"`} value={d.actor.height} onChange={(e) => setActor("height", e.target.value)} />
              </Field>
              <Field label="Ethnic appearance">
                <input className={field} maxLength={120} value={d.actor.ethnicAppearance} onChange={(e) => setActor("ethnicAppearance", e.target.value)} />
              </Field>
              <Field label="Hair">
                <input className={field} maxLength={40} value={d.actor.hair} onChange={(e) => setActor("hair", e.target.value)} />
              </Field>
              <Field label="Eyes">
                <input className={field} maxLength={40} value={d.actor.eyes} onChange={(e) => setActor("eyes", e.target.value)} />
              </Field>
              <Field label="Union">
                <select className={field} value={d.actor.union} onChange={(e) => setActor("union", e.target.value)}>
                  <option value="">Not set</option>
                  {UNIONS.map((u) => (
                    <option key={u}>{u}</option>
                  ))}
                </select>
              </Field>
              <Field label="Based in">
                <input className={field} maxLength={80} placeholder="Austin, TX" value={d.actor.basedIn} onChange={(e) => setActor("basedIn", e.target.value)} />
              </Field>
            </div>
          </Section>

          <Section title="Skills & training">
            <Field label="Special skills">
              <textarea className={field} rows={2} maxLength={600} placeholder="Guitar, stage combat, horseback riding" value={d.actor.specialSkills} onChange={(e) => setActor("specialSkills", e.target.value)} />
            </Field>
            <Field label="Languages">
              <input className={field} maxLength={300} value={d.actor.languages} onChange={(e) => setActor("languages", e.target.value)} />
            </Field>
            <Field label="Training">
              <textarea className={field} rows={2} maxLength={600} value={d.actor.training} onChange={(e) => setActor("training", e.target.value)} />
            </Field>
          </Section>

          <Section title="More resume credits" note="Roles you're credited for on Nexus are added automatically. Add plays, commercials and anything else here.">
            <div className="space-y-3">
              {d.actor.resume.map((c, i) => (
                <div key={c.id} className="grid gap-2 rounded-xl border border-border p-3 sm:grid-cols-[8rem_1fr_1fr]">
                  <select className={field} value={c.category} onChange={(e) => setCredit(i, { category: e.target.value })}>
                    {RESUME_CATEGORIES.map((cat) => (
                      <option key={cat}>{cat}</option>
                    ))}
                  </select>
                  <input className={field} placeholder="Project" value={c.project} onChange={(e) => setCredit(i, { project: e.target.value })} />
                  <input className={field} placeholder="Role" value={c.role} onChange={(e) => setCredit(i, { role: e.target.value })} />
                  <input className={`${field} sm:col-span-2`} placeholder="Director or company" value={c.company} onChange={(e) => setCredit(i, { company: e.target.value })} />
                  <div className="flex gap-2">
                    <input className={field} inputMode="numeric" placeholder="Year" value={c.year} onChange={(e) => setCredit(i, { year: e.target.value.replace(/\D/g, "").slice(0, 4) })} />
                    <button
                      type="button"
                      aria-label="Remove credit"
                      onClick={() => setActor("resume", d.actor.resume.filter((_, j) => j !== i))}
                      className="rounded-xl border border-border px-3 text-sm text-muted hover:bg-surface"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              ))}
              <button
                type="button"
                onClick={() =>
                  setActor("resume", [...d.actor.resume, { id: crypto.randomUUID(), category: "Film", project: "", role: "", company: "", year: "" }])
                }
                className="rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-surface"
              >
                + Add credit
              </button>
            </div>
          </Section>
        </>
      )}

      {style === "Filmmaker" && (
        <Section title="Filmmaker" note="Your filmography and stills come from what you're credited on. Your role tags decide which crew calls show up on Now.">
          <Field label="Specialties">
            <textarea className={field} rows={2} maxLength={400} placeholder="Handheld docs, color grading" value={d.filmmaker.specialties} onChange={(e) => setFilmmaker("specialties", e.target.value)} />
          </Field>
          <Field label="Gear">
            <textarea className={field} rows={2} maxLength={400} value={d.filmmaker.gear} onChange={(e) => setFilmmaker("gear", e.target.value)} />
          </Field>
          <label className="flex items-center gap-3 text-sm font-medium">
            <input type="checkbox" checked={d.filmmaker.openToCrew} onChange={(e) => setFilmmaker("openToCrew", e.target.checked)} className="h-4 w-4 accent-[var(--brand)]" />
            Open to joining crews
          </label>
        </Section>
      )}

      {style === "Musician" && (
        <Section title="Musician" note="Releases under this artist name, or crediting you, make up your discography.">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Artist or band name">
              <input className={field} maxLength={80} value={d.musician.artistName} onChange={(e) => setMusician("artistName", e.target.value)} />
            </Field>
            <Field label="Genres">
              <input className={field} maxLength={200} value={d.musician.genres} onChange={(e) => setMusician("genres", e.target.value)} />
            </Field>
            <Field label="Instruments">
              <input className={field} maxLength={200} value={d.musician.instruments} onChange={(e) => setMusician("instruments", e.target.value)} />
            </Field>
          </div>
          <div className="space-y-2">
            <p className="text-sm font-medium">Available for</p>
            {(
              [
                ["availableForGigs", "Live gigs"],
                ["availableForSessions", "Session work"],
                ["availableForScoring", "Scoring films"],
              ] as const
            ).map(([key, label]) => (
              <label key={key} className="flex items-center gap-3 text-sm">
                <input type="checkbox" checked={d.musician[key]} onChange={(e) => setMusician(key, e.target.checked)} className="h-4 w-4 accent-[var(--brand)]" />
                {label}
              </label>
            ))}
          </div>
        </Section>
      )}

      {error && <p className="rounded-xl bg-red-500/10 p-3 text-sm text-red-500">{error}</p>}

      <div className="flex gap-3">
        <button type="submit" disabled={pending || !style} className="rounded-full bg-brand px-6 py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60">
          {pending ? "Saving…" : "Save"}
        </button>
        <Link href="/portfolio" className="rounded-full border border-border px-6 py-2.5 text-sm font-semibold hover:bg-surface">
          Cancel
        </Link>
      </div>
    </form>
  );
}
