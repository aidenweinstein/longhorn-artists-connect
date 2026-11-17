"use client";

import { useEffect, useState, type Dispatch, type ReactNode, type SetStateAction } from "react";
import {
  GENDERS,
  GENRE_OPTIONS,
  INSTRUMENT_OPTIONS,
  RESUME_CATEGORIES,
  STREAMING_SERVICES,
  UNIONS,
  splitList,
  type CreativeDetails,
  type ResumeCredit,
} from "@/lib/profileStyle";

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
  for (const k of ["gender", "height", "ethnicAppearance", "hair", "eyes", "union", "languages", "specialSkills", "training"] as const) {
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
  form.set("soloName", m.soloName);
  form.set("bandName", m.bandName);
  form.set("instruments", m.instruments);
  form.set("genres", m.genres);
  for (const { name } of STREAMING_SERVICES) form.set(`stream:${name}`, m.streamingLinks[name] ?? "");
  form.set("studios", d.filmmaker.studios);
  form.set("certifications", d.filmmaker.certifications);
  form.set("gear", d.filmmaker.gear);
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

/** A row that opens a panel from the right, showing what's chosen so far. */
function PanelRow({ label, value, onOpen }: { label: string; value: string; onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full items-center gap-3 rounded-xl border border-border bg-background px-3 py-2.5 text-left text-sm hover:bg-surface"
    >
      <span className="font-medium">{label}</span>
      <span className="ml-auto min-w-0 truncate text-muted">{value || "None"}</span>
      <span aria-hidden className="text-muted">›</span>
    </button>
  );
}

/** A page that slides in from the right over the form. Escape or Done closes it. */
function SidePanel({ title, note, onClose, children }: { title: string; note?: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <button type="button" aria-label="Close" onClick={onClose} className="absolute inset-0 bg-black/40" />
      <div role="dialog" aria-modal="true" aria-label={title} className="relative flex h-full w-full max-w-md flex-col bg-background shadow-2xl">
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <h3 className="text-lg font-bold">{title}</h3>
          <button type="button" onClick={onClose} className="rounded-full bg-brand px-4 py-1.5 text-sm font-semibold text-white">
            Done
          </button>
        </div>
        <div className="flex-1 space-y-4 overflow-y-auto p-5">
          {note && <p className="text-sm text-muted">{note}</p>}
          {children}
        </div>
      </div>
    </div>
  );
}

/** Tappable chips for a comma-separated list. Values not in `options` (typed in older builds) stay as selected chips. */
function ChipPicker({ options, value, onChange }: { options: string[]; value: string; onChange: (v: string) => void }) {
  const selected = splitList(value);
  const has = (chip: string) => selected.some((x) => x.toLowerCase() === chip.toLowerCase());
  const chips = [...options, ...selected.filter((x) => !options.some((o) => o.toLowerCase() === x.toLowerCase()))];
  const toggle = (chip: string) =>
    onChange((has(chip) ? selected.filter((x) => x.toLowerCase() !== chip.toLowerCase()) : [...selected, chip]).join(", "));
  return (
    <div className="flex flex-wrap gap-1.5">
      {chips.map((chip) => (
        <button
          key={chip}
          type="button"
          aria-pressed={has(chip)}
          onClick={() => toggle(chip)}
          className={`rounded-full px-3 py-1.5 text-xs font-medium ${has(chip) ? "bg-brand text-white" : "bg-surface hover:bg-border"}`}
        >
          {chip}
        </button>
      ))}
    </div>
  );
}

type Panel = "streaming" | "instruments" | "genres";

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
  const [panel, setPanel] = useState<Panel | null>(null);
  const close = () => setPanel(null);
  // A union saved before the list changed (e.g. "SAG-AFTRA") stays selectable until they pick another.
  const unions = d.actor.union && !UNIONS.includes(d.actor.union) ? [...UNIONS, d.actor.union] : UNIONS;

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
          <Field label="Gender">
            <select className={field} value={d.actor.gender} onChange={(e) => setActor("gender", e.target.value)}>
              <option value="">Not set</option>
              {GENDERS.map((g) => (
                <option key={g}>{g}</option>
              ))}
            </select>
          </Field>
          <div>
            <span className="mb-1.5 block text-sm font-medium">Playable age</span>
            <div className="flex items-center gap-2">
              <input aria-label="Youngest playable age" className={field} inputMode="numeric" placeholder="18" value={draft.ageMin} onChange={(e) => setDraft((c) => ({ ...c, ageMin: digits(e.target.value, 2) }))} />
              <span className="text-muted">–</span>
              <input aria-label="Oldest playable age" className={field} inputMode="numeric" placeholder="25" value={draft.ageMax} onChange={(e) => setDraft((c) => ({ ...c, ageMax: digits(e.target.value, 2) }))} />
            </div>
          </div>
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
              {unions.map((u) => (
                <option key={u}>{u}</option>
              ))}
            </select>
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

      <Section id="filmmaker-info" title="Filmmaker Info" note="Your filmography and stills come from what you're credited on.">
        <Field label="Studio(s)">
          <textarea className={field} rows={2} maxLength={400} value={d.filmmaker.studios} onChange={(e) => setFilmmaker("studios", e.target.value)} />
        </Field>
        <Field label="Software">
          <textarea className={field} rows={2} maxLength={400} placeholder="Adobe Premiere Pro, Avid Media Composer" value={d.filmmaker.certifications} onChange={(e) => setFilmmaker("certifications", e.target.value)} />
        </Field>
        <Field label="Gear">
          <textarea className={field} rows={2} maxLength={400} value={d.filmmaker.gear} onChange={(e) => setFilmmaker("gear", e.target.value)} />
        </Field>
      </Section>

      <Section id="musician-info" title="Musician Info" note="Releases under your solo act or band name, or crediting you, make up your discography.">
        <PanelRow
          label="Streaming pages"
          value={STREAMING_SERVICES.filter(({ name }) => d.musician.streamingLinks[name]).map(({ name }) => name).join(", ")}
          onOpen={() => setPanel("streaming")}
        />
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Solo act name">
            <input className={field} maxLength={80} value={d.musician.soloName} onChange={(e) => setMusician("soloName", e.target.value)} />
          </Field>
          <Field label="Band name">
            <input className={field} maxLength={80} value={d.musician.bandName} onChange={(e) => setMusician("bandName", e.target.value)} />
          </Field>
        </div>
        <PanelRow label="Instruments" value={splitList(d.musician.instruments).join(", ")} onOpen={() => setPanel("instruments")} />
        <PanelRow label="Genres" value={splitList(d.musician.genres).join(", ")} onOpen={() => setPanel("genres")} />
      </Section>

      {panel === "streaming" && (
        <SidePanel title="Streaming pages" note="Paste the link to your Spotify page (and any others); they appear as buttons on your profile." onClose={close}>
          {STREAMING_SERVICES.map(({ name, placeholder }) => (
            <Field key={name} label={name}>
              <input
                className={field}
                inputMode="url"
                maxLength={300}
                placeholder={placeholder}
                value={d.musician.streamingLinks[name] ?? ""}
                onChange={(e) => setMusician("streamingLinks", { ...d.musician.streamingLinks, [name]: e.target.value })}
              />
            </Field>
          ))}
        </SidePanel>
      )}
      {panel === "instruments" && (
        <SidePanel title="Instruments" note="Everything you can play." onClose={close}>
          <ChipPicker options={INSTRUMENT_OPTIONS} value={d.musician.instruments} onChange={(v) => setMusician("instruments", v)} />
        </SidePanel>
      )}
      {panel === "genres" && (
        <SidePanel title="Genres" onClose={close}>
          <ChipPicker options={GENRE_OPTIONS} value={d.musician.genres} onChange={(v) => setMusician("genres", v)} />
        </SidePanel>
      )}
    </>
  );
}
