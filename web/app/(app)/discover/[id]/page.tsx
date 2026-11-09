import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import ImageCarousel from "@/components/ImageCarousel";
import MaskImage from "@/components/MaskImage";
import PersonLink from "@/components/PersonLink";
import { allDiscoverIDs, findDiscoverItem } from "@/lib/content";
import type { NexusEvent, Project } from "@/lib/discoverContent";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";

// Full detail for a Discover project or event, with every field the app stores.
// Mirrors UpcomingProjectDetailView (ProjectCard.swift) and EventDetailView (EventCard.swift).

export async function generateStaticParams() {
  return (await allDiscoverIDs()).map((id) => ({ id }));
}

const TZ = "America/Chicago";
const longDate = new Intl.DateTimeFormat("en-US", { weekday: "long", month: "short", day: "numeric", year: "numeric", timeZone: TZ });
const shortDate = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: TZ });
const time = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: TZ });
const dayKey = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: TZ });
const posted = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: TZ });

const sameDay = (a: number, b: number) => dayKey.format(a) === dayKey.format(b);
const t = (ms: number) => time.format(ms).replace(" ", "").toLowerCase();

/** The app's lineup label for each event category, or nothing for categories without one. */
const LINEUP_LABEL: Record<string, string> = {
  Concert: "Artists",
  Showcase: "Actors",
  "Theatre Performance": "Cast",
  "Film Festival": "Films",
  Speaker: "Speakers",
};

export default async function DiscoverDetail(props: PageProps<"/discover/[id]">) {
  const { id } = await props.params;
  const item = await findDiscoverItem(id);
  if (!item) notFound();
  return item.kind === "project" ? <ProjectDetail p={item} /> : <EventDetail e={item} />;
}

// MARK: - Layout pieces

function Shell({ media, children }: { media: ReactNode; children: ReactNode }) {
  return (
    <div className="mx-auto flex max-w-[1400px] flex-col gap-8 lg:flex-row lg:items-start">
      <div className="w-full lg:sticky lg:top-3 lg:w-[min(46%,560px)] lg:shrink-0">{media}</div>
      <div className="min-w-0 flex-1 space-y-6">{children}</div>
    </div>
  );
}

function Placeholder({ kind }: { kind: "project" | "event" }) {
  const type = DISCOVER_TYPES.find((d) => d.id === kind)!;
  return (
    <div
      className={`flex aspect-[2/3] w-full max-w-sm items-center justify-center rounded-2xl bg-gradient-to-br ${
        kind === "project" ? "from-[#3a1d08] to-[#bf5700]" : "from-[#2b1240] to-[#c2410c]"
      }`}
    >
      <MaskImage src={type.icon} ratio={type.ratio} className="h-16 text-white/40" />
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="rounded-2xl bg-surface p-5">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">{title}</h2>
      <div className="mt-3">{children}</div>
    </section>
  );
}

/** Label on the left, value on the right, one row per field, like the app's detailRow. */
function Rows({ rows }: { rows: [string, ReactNode][] }) {
  return (
    <ul className="divide-y divide-border">
      {rows.map(([label, value], i) => (
        <li key={`${label}-${i}`} className="flex items-start justify-between gap-6 py-2.5 text-sm">
          <span className="shrink-0 text-muted">{label}</span>
          <span className="min-w-0 text-right font-medium">{value}</span>
        </li>
      ))}
    </ul>
  );
}

function Footer({ by, byID, createdAt, editedAt }: { by?: string; byID?: string; createdAt?: number; editedAt?: number }) {
  const parts: ReactNode[] = [];
  if (by) parts.push(<span key="by">Posted by <PersonLink name={by} profileID={byID} className="font-medium text-foreground" /></span>);
  if (createdAt) parts.push(<span key="on">{posted.format(createdAt)}</span>);
  if (editedAt && (!createdAt || editedAt - createdAt > 60_000)) parts.push(<span key="ed">Edited {posted.format(editedAt)}</span>);
  if (!parts.length) return null;
  return (
    <p className="flex flex-wrap gap-x-2 text-sm text-muted">
      {parts.map((p, i) => (
        <span key={i} className="flex gap-x-2">
          {i > 0 && <span aria-hidden>·</span>}
          {p}
        </span>
      ))}
    </p>
  );
}

const button =
  "inline-flex items-center gap-2 rounded-full bg-brand px-6 py-2.5 text-sm font-semibold text-white transition hover:brightness-110";

const safeUrl = (u?: string) => {
  if (!u) return undefined;
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : `https://${u}`;
  return /^https?:\/\//i.test(withScheme) ? withScheme : undefined;
};

// MARK: - Project

function ProjectDetail({ p }: { p: Project }) {
  // The app shows slides first and ends the slideshow on the poster.
  const pictures = [...(p.slides ?? []), ...(p.posterUrl ? [p.posterUrl] : [])];
  const open = p.castNeeded.length + p.crewNeeded.length > 0;
  const shooting = p.shootDates || (p.shootStart ? shortDate.format(p.shootStart) : "");
  const release = p.releaseDate || (p.releaseDateAt ? posted.format(p.releaseDateAt) : "");

  const details: [string, ReactNode][] = [];
  if (p.genres?.length) details.push(["Genres", p.genres.join(", ")]);
  if (shooting) details.push(["Shooting", shooting]);
  if (release) details.push(["Expected Release", release]);
  if (p.writers) details.push(["Written by", p.writers]);
  if (p.scriptPages) details.push(["Script", `${p.scriptPages} pages`]);

  return (
    <Shell media={pictures.length ? <ImageCarousel images={pictures} aspect={2 / 3} /> : <Placeholder kind="project" />}>
      <div>
        <p className="text-sm font-semibold uppercase tracking-wide text-brand">{p.projectType}</p>
        <h1 className="mt-1 text-3xl font-bold leading-tight">{p.title}</h1>
        {p.castNeeded.length + p.crewNeeded.length + (p.castAssembled?.length ?? 0) + (p.crewAssembled?.length ?? 0) > 0 && (
          <span
            className={`mt-3 inline-block rounded-full px-3 py-1 text-xs font-semibold ${open ? "bg-brand text-white" : "bg-foreground/10 text-muted"}`}
          >
            {p.castNeeded.length && p.crewNeeded.length
              ? "Cast & Crew Needed"
              : p.castNeeded.length
                ? "Cast Needed"
                : p.crewNeeded.length
                  ? "Crew Needed"
                  : "Team Assembled"}
          </span>
        )}
        {p.logline && <p className="mt-4 whitespace-pre-line leading-relaxed text-foreground/85">{p.logline}</p>}
      </div>

      {details.length > 0 && (
        <Section title="Details">
          <Rows rows={details} />
        </Section>
      )}

      {p.castNeeded.length > 0 && (
        <Section title="Cast Call">
          <Rows
            rows={p.castNeeded.map((entry) => {
              // Stored as "Role: description" (CastRoleFormat).
              const i = entry.indexOf(": ");
              return i < 0 ? [entry, ""] : [entry.slice(0, i), <span key="d" className="font-normal text-foreground/85">{entry.slice(i + 2)}</span>];
            })}
          />
        </Section>
      )}

      {p.crewNeeded.length > 0 && (
        <Section title="Crew Call">
          <div className="flex flex-wrap gap-2">
            {p.crewNeeded.map((role) => (
              <span key={role} className="rounded-full bg-foreground/10 px-3.5 py-1.5 text-sm font-medium">
                {role}
              </span>
            ))}
          </div>
        </Section>
      )}

      {!!p.crewAssembled?.length && (
        <Section title="Crew">
          <Rows rows={groupRoles(p.crewAssembled).map((c) => [c.roles.join(", "), <PersonLink key={c.name} name={c.name} profileID={c.profileID} />])} />
        </Section>
      )}

      {!!p.castAssembled?.length && (
        <Section title="Cast">
          <Rows rows={p.castAssembled.map((c) => [c.role, <PersonLink key={c.name} name={c.name} profileID={c.profileID} />])} />
        </Section>
      )}

      <Footer by={p.postedBy} byID={p.postedByProfileID} createdAt={p.createdAt} editedAt={p.editedAt} />
    </Shell>
  );
}

/** One row per crew member, listing every role they hold (the app's consolidatedCrew). */
function groupRoles(credits: { role: string; name: string; profileID?: string }[]) {
  const rows = new Map<string, { name: string; profileID?: string; roles: string[] }>();
  for (const c of credits) {
    const key = c.name.trim().toLowerCase();
    const row = rows.get(key) ?? { name: c.name, profileID: c.profileID, roles: [] };
    if (c.role && !row.roles.includes(c.role)) row.roles.push(c.role);
    row.profileID ??= c.profileID;
    rows.set(key, row);
  }
  return [...rows.values()];
}

// MARK: - Event

function eventDateLine(e: NexusEvent): string | undefined {
  const shows = e.showings ?? [];
  // A run spans its first through last performance.
  if (shows.length > 1 && !sameDay(shows[0][0], shows.at(-1)![0])) {
    return `${longDate.format(shows[0][0])} – ${longDate.format(shows.at(-1)![0])}`;
  }
  if (!e.startsAt) return undefined;
  if (e.category === "Recruitment Schedule") {
    return e.endsAt ? `${longDate.format(e.startsAt)} – ${longDate.format(e.endsAt)}` : longDate.format(e.startsAt);
  }
  if (e.endsAt && sameDay(e.startsAt, e.endsAt)) return `${longDate.format(e.startsAt)} • ${t(e.startsAt)} – ${t(e.endsAt)}`;
  if (e.endsAt) return `${longDate.format(e.startsAt)} ${t(e.startsAt)} – ${longDate.format(e.endsAt)} ${t(e.endsAt)}`;
  return `${longDate.format(e.startsAt)} • ${t(e.startsAt)}`;
}

function EventDetail({ e }: { e: NexusEvent }) {
  const dateLine = eventDateLine(e);
  const shows = e.showings ?? [];
  const tickets = safeUrl(e.ticketsUrl);
  const apply = safeUrl(e.applyUrl);
  const lineupLabel = e.category ? LINEUP_LABEL[e.category] : undefined;

  const details: [string, ReactNode][] = [];
  if (e.host) details.push(["Host", e.host]);
  if (e.category) details.push(["Category", e.category]);
  if (e.lineup?.length) details.push([lineupLabel ?? "Lineup", e.lineup.join(", ")]);
  if (e.expectations) details.push(["Entry Requirements", <span key="x" className="whitespace-pre-line font-normal text-foreground/85">{e.expectations}</span>]);
  details.push(["Admission", tickets ? "Ticketed" : "Free"]);

  return (
    <Shell media={e.flyerUrl ? <ImageCarousel images={[e.flyerUrl]} aspect={2 / 3} /> : <Placeholder kind="event" />}>
      <div>
        {e.category && <p className="text-sm font-semibold uppercase tracking-wide text-brand">{e.category}</p>}
        <h1 className="mt-1 text-3xl font-bold leading-tight">{e.title}</h1>
        {dateLine && <p className="mt-2 text-lg font-semibold">{dateLine}</p>}

        {shows.length > 1 && (
          <div className="mt-3">
            <p className="text-sm font-semibold text-muted">Showings</p>
            <ul className="mt-1 space-y-0.5 text-sm">
              {shows.map(([start, end]) => (
                <li key={start}>
                  {shortDate.format(start)} • {t(start)}
                  {sameDay(start, end) ? ` – ${t(end)}` : ""}
                </li>
              ))}
            </ul>
          </div>
        )}

        {e.location && (
          <a
            href={`https://maps.apple.com/?q=${encodeURIComponent(e.location)}`}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-3 inline-flex items-center gap-1.5 font-medium text-brand hover:underline"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
              <path d="M12 2a7 7 0 0 0-7 7c0 5.2 7 13 7 13s7-7.8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z" />
            </svg>
            {e.location}
          </a>
        )}

        {e.logline && <p className="mt-4 whitespace-pre-line leading-relaxed text-foreground/85">{e.logline}</p>}

        {(tickets || apply) && (
          <div className="mt-5">
            <a href={tickets ?? apply} target="_blank" rel="noopener noreferrer" className={button}>
              {tickets ? "Buy Ticket" : "Apply"}
            </a>
          </div>
        )}
      </div>

      <Section title="Details">
        <Rows rows={details} />
      </Section>

      <Footer by={e.postedBy} byID={e.postedByProfileID} createdAt={e.createdAt} editedAt={e.editedAt} />
    </Shell>
  );
}
