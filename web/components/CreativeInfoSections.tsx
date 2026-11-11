"use client";

import type { Dispatch, ReactNode, SetStateAction } from "react";
import { GENDERS, RESUME_CATEGORIES, UNIONS, type CreativeDetails, type ResumeCredit } from "@/lib/profileStyle";

/*
 * The Actor Info, Filmmaker Info and Musician Info sections of Edit profile.
 * Anyone can fill in any of them; whatever is filled in shows on their portfolio.
 */

const field = "w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-brand";

export type CreativeDraft = { details: CreativeDetails; ageMin: string; ageMax: string };

export const draftFrom = (details: CreativeDetails): CreativeDraft => ({
  details,
  ageMin: details.actor.ageMin?.toString() ?? "",
  ageMax: details.actor.ageMax?.toString() ?? "",
});

/** Adds the three sections to the form sent to saveProfile (read back by detailsFromForm). */
export function appendCreative(form: FormData, { details: d, ageMin, ageMax }: CreativeDraft) {
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
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium">{label}</span>
      {children}
    </label>
  );
}

function Section({ id, title, note, children }: { id: string; title: string; note: string; children: ReactNode }) {
  return (
    <section id={id} className="scroll-mt-24 space-y-5 border-t border-border pt-8">
      <div>
        <h2 className="text-xl font-bold">{title}</h2>
        <p className="mt-0.5 text-sm text-muted">{note}</p>
      </div>
      {children}
    </section>
  );
}

function Sub({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold">{title}</h3>
        {note && <p className="text-xs text-muted">{note}</p>}
      </div>
      {children}
    </div>
  );
}

export default function CreativeInfoSections({
  draft,
  setDraft,
  headshotUrl,
  onHeadshot,
  reels,
}: {
  draft: CreativeDraft;
  setDraft: Dispatch<SetStateAction<CreativeDraft>>;
  /** The saved headshot, or a preview of the one just chosen. */
  headshotUrl?: string;
  onHeadshot: (file: File | undefined) => void;
  /** Performances and Films they're credited on, to pick a reel from. */
  reels: { id: string; title: string }[];
}) {
  const d = draft.details;
  const setD = (change: (c: CreativeDetails) => CreativeDetails) => setDraft((cur) => ({ ...cur, details: change(cur.details) }));
  const setActor = <K extends keyof CreativeDetails["actor"]>(k: K, v: CreativeDetails["actor"][K]) =>
    setD((c) => ({ ...c, actor: { ...c.actor, [k]: v } }));
  const setMusician = <K extends keyof CreativeDetails["musician"]>(k: K, v: CreativeDetails["musician"][K]) =>
    setD((c) => ({ ...c, musician: { ...c.musician, [k]: v } }));
  const setFilmmaker = <K extends keyof CreativeDetails["filmmaker"]>(k: K, v: CreativeDetails["filmmaker"][K]) =>
    setD((c) => ({ ...c, filmmaker: { ...c.filmmaker, [k]: v } }));
  const setCredit = (i: number, patch: Partial<ResumeCredit>) =>
    setActor("resume", d.actor.resume.map((c, j) => (j === i ? { ...c, ...patch } : c)));
  const digits = (v: string, max: number) => v.replace(/\D/g, "").slice(0, max);

  return (
    <>
      <Section id="actor-info" title="Actor Info" note="Headshot, reel, stats and resume. Age, gender, look and skills also decide which open roles Nexus suggests to you.">
        <Sub title="Headshot">
          <div className="flex items-center gap-5">
            {headshotUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={headshotUrl} alt="" className="h-40 w-[7.5rem] shrink-0 rounded-lg object-cover" />
            ) : (
              <span className="flex h-40 w-[7.5rem] shrink-0 items-center justify-center rounded-lg bg-surface text-xs text-muted">No headshot</span>
            )}
            <label className="cursor-pointer rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-surface">
              {headshotUrl ? "Change headshot" : "Add headshot"}
              <input type="file" accept="image/jpeg,image/png,image/*" className="sr-only" onChange={(e) => onHeadshot(e.target.files?.[0])} />
            </label>
          </div>
        </Sub>

        <Sub title="Reel" note={reels.length ? "A Performance or Film you're credited on." : "Post a Performance or Film you're credited on to use it as your reel."}>
          <select aria-label="Reel" className={field} value={d.actor.reelPostID ?? ""} onChange={(e) => setActor("reelPostID", e.target.value || undefined)}>
            <option value="">None</option>
            {reels.map((r) => (
              <option key={r.id} value={r.id}>
                {r.title}
              </option>
            ))}
          </select>
        </Sub>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <span className="mb-1.5 block text-sm font-medium">Playable age</span>
            <div className="flex items-center gap-2">
              <input aria-label="Youngest playable age" className={field} inputMode="numeric" placeholder="18" value={draft.ageMin} onChange={(e) => setDraft((c) => ({ ...c, ageMin: digits(e.target.value, 2) }))} />
              <span className="text-muted">–</span>
              <input aria-label="Oldest playable age" className={field} inputMode="numeric" placeholder="25" value={draft.ageMax} onChange={(e) => setDraft((c) => ({ ...c, ageMax: digits(e.target.value, 2) }))} />
            </div>
          </div>
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

        <Field label="Special skills">
          <textarea className={field} rows={2} maxLength={600} placeholder="Guitar, stage combat, horseback riding" value={d.actor.specialSkills} onChange={(e) => setActor("specialSkills", e.target.value)} />
        </Field>
        <Field label="Languages">
          <input className={field} maxLength={300} value={d.actor.languages} onChange={(e) => setActor("languages", e.target.value)} />
        </Field>
        <Field label="Training">
          <textarea className={field} rows={2} maxLength={600} value={d.actor.training} onChange={(e) => setActor("training", e.target.value)} />
        </Field>

        <Sub title="More resume credits" note="Roles you're credited for on Nexus are added automatically. Add plays, commercials and anything else here.">
          <div className="space-y-3">
            {d.actor.resume.map((c, i) => (
              <div key={c.id} className="grid gap-2 rounded-xl border border-border p-3 sm:grid-cols-[8rem_1fr_1fr]">
                <select aria-label="Category" className={field} value={c.category} onChange={(e) => setCredit(i, { category: e.target.value })}>
                  {RESUME_CATEGORIES.map((cat) => (
                    <option key={cat}>{cat}</option>
                  ))}
                </select>
                <input aria-label="Project" className={field} maxLength={120} placeholder="Project" value={c.project} onChange={(e) => setCredit(i, { project: e.target.value })} />
                <input aria-label="Role" className={field} maxLength={120} placeholder="Role" value={c.role} onChange={(e) => setCredit(i, { role: e.target.value })} />
                <input aria-label="Director or company" className={`${field} sm:col-span-2`} maxLength={120} placeholder="Director or company" value={c.company} onChange={(e) => setCredit(i, { company: e.target.value })} />
                <div className="flex gap-2">
                  <input aria-label="Year" className={field} inputMode="numeric" placeholder="Year" value={c.year} onChange={(e) => setCredit(i, { year: digits(e.target.value, 4) })} />
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
              onClick={() => setActor("resume", [...d.actor.resume, { id: crypto.randomUUID(), category: "Film", project: "", role: "", company: "", year: "" }])}
              className="rounded-full border border-border px-4 py-2 text-sm font-semibold hover:bg-surface"
            >
              + Add credit
            </button>
          </div>
        </Sub>
      </Section>

      <Section id="filmmaker-info" title="Filmmaker Info" note="Your filmography and stills come from what you're credited on. Add what you specialize in and shoot with.">
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

      <Section id="musician-info" title="Musician Info" note="Releases under this artist name, or crediting you, make up your discography.">
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
    </>
  );
}
