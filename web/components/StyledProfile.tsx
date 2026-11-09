import Link from "next/link";
import Timecode from "./Timecode";
import type { Account } from "@/lib/cloudkit/content";
import type { NexusEvent } from "@/lib/discoverContent";
import type { Post } from "@/lib/mockContent";
import {
  actorStats,
  creditsFor,
  matchesPerson,
  musicianAvailability,
  type CreativeProfile,
} from "@/lib/profileStyle";

/*
 * The part of a portfolio that changes with the person's profile style, shown between
 * the header and their Work grid:
 *   Actor      — like Actors Access: headshot beside the stats sheet, reel, resume, skills.
 *   Filmmaker  — like IMDb: filmography grouped by job, newest first, then a grid of stills.
 *   Musician   — like Spotify: upcoming shows, songs, albums & EPs.
 */

const dayFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "America/Chicago" });
const timeFmt = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", timeZone: "America/Chicago" });

const year = (p: Post) => p.details?.releaseYear ?? "";
const kind = (p: Post) =>
  p.details?.kindLabel || ({ film: "Film", music: "Music", performance: "Performance", design: "Design", photography: "Photography" } as const)[p.category];

function H({ children }: { children: React.ReactNode }) {
  return <h2 className="mb-3 text-xl font-bold">{children}</h2>;
}

/** Upcoming events this person is on: posted, in the lineup, or under their artist name. */
export function upcomingShowsFor(events: NexusEvent[], person: { name: string; profileID: string }, artistName = ""): NexusEvent[] {
  const now = Date.now() - 6 * 60 * 60 * 1000;
  const names = [person.name, artistName].map((x) => x.trim().toLowerCase()).filter(Boolean);
  return events
    .filter((e) => (e.endsAt ?? e.startsAt ?? 0) >= now)
    .filter(
      (e) =>
        matchesPerson(e.postedBy ?? "", e.postedByProfileID, person) ||
        (e.lineup ?? []).some((l) => names.some((n) => l.toLowerCase().includes(n))),
    )
    .sort((a, b) => (a.startsAt ?? 0) - (b.startsAt ?? 0));
}

export default function StyledProfile({
  account,
  posts,
  creative,
  events,
  isOwn = false,
}: {
  account: Account;
  /** Posts this person is credited on. */
  posts: Post[];
  creative: CreativeProfile | null;
  /** Every Discover event, to find their upcoming shows. */
  events: NexusEvent[];
  isOwn?: boolean;
}) {
  if (!creative) {
    if (!isOwn) return null;
    return (
      <div className="mt-8 rounded-2xl border border-dashed border-border p-6">
        <p className="font-semibold">Choose your profile style</p>
        <p className="mt-1 text-sm text-muted">Filmmaker, Actor or Musician. It decides how your profile looks and what Nexus recommends to you.</p>
        <Link href="/portfolio/style" className="mt-3 inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          Choose style
        </Link>
      </div>
    );
  }

  const person = { name: account.name, profileID: account.profileID };
  return (
    <div className="mt-8 space-y-10">
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-wider text-muted">{creative.style}</p>
        {isOwn && (
          <Link href="/portfolio/style" className="text-sm font-semibold text-brand hover:underline">
            Edit {creative.style.toLowerCase()} profile
          </Link>
        )}
      </div>
      {creative.style === "Actor" && <ActorProfile creative={creative} posts={posts} person={person} isOwn={isOwn} name={account.name} />}
      {creative.style === "Filmmaker" && <FilmmakerProfile creative={creative} posts={posts} person={person} isOwn={isOwn} />}
      {creative.style === "Musician" && <MusicianProfile creative={creative} posts={posts} person={person} events={events} isOwn={isOwn} />}
    </div>
  );
}

type Person = { name: string; profileID: string };

// MARK: - Actor (Actors Access)

function ActorProfile({ creative, posts, person, isOwn, name }: { creative: CreativeProfile; posts: Post[]; person: Person; isOwn: boolean; name: string }) {
  const a = creative.details.actor;
  const stats = actorStats(a);
  const reel = a.reelPostID ? posts.find((p) => p.id === a.reelPostID) : undefined;

  // Resume: Nexus roles (cast credits, or any credit on a Performance) plus typed-in ones.
  type Line = { category: string; project: string; role: string; company: string; year: string; href?: string };
  const lines: Line[] = [];
  for (const post of posts) {
    const mine = creditsFor(post, person);
    const acting = mine.filter((m) => m.group === "Cast" || post.category === "performance");
    if (!acting.length) continue;
    const director = post.details?.creditGroups.flatMap((g) => g.credits).find((c) => c.role.trim().toLowerCase() === "director")?.name ?? "";
    lines.push({
      category: post.category === "performance" ? "Performance" : "Film",
      project: post.title,
      role: acting.map((m) => m.credit.role).filter(Boolean).join(", "),
      company: director,
      year: year(post),
      href: `/post/${post.id}`,
    });
  }
  for (const c of a.resume) lines.push({ category: c.category, project: c.project, role: c.role, company: c.company, year: c.year });
  const order = ["Film", "Television", "Theatre", "Performance", "Commercial", "New Media", "Other"];
  const categories = [...order.filter((c) => lines.some((l) => l.category === c)), ...[...new Set(lines.map((l) => l.category))].filter((c) => !order.includes(c))];
  const extras = [
    ["Special skills", a.specialSkills],
    ["Languages", a.languages],
    ["Training", a.training],
  ].filter(([, v]) => v.trim());

  return (
    <>
      <section className="grid gap-6 sm:grid-cols-[12rem_minmax(0,1fr)] lg:grid-cols-[14rem_minmax(0,1fr)_minmax(0,1.2fr)]">
        {creative.headshotUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={creative.headshotUrl} alt={`${name} headshot`} className="aspect-[3/4] w-full rounded-lg object-cover" />
        ) : (
          <div className="flex aspect-[3/4] w-full items-center justify-center rounded-lg bg-surface text-sm text-muted">No headshot</div>
        )}
        <div>
          {stats.length === 0 ? (
            <p className="text-sm text-muted">{isOwn ? "Add your age range, height and more with Edit." : "No details yet."}</p>
          ) : (
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
              {stats.map((s) => (
                <div key={s.label} className="contents">
                  <dt className="text-muted">{s.label}</dt>
                  <dd className="font-medium">{s.value}</dd>
                </div>
              ))}
            </dl>
          )}
          {extras.length > 0 && (
            <div className="mt-5 space-y-3 lg:hidden">
              {extras.map(([label, value]) => (
                <div key={label}>
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted">{label}</p>
                  <p className="whitespace-pre-line text-sm">{value}</p>
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="hidden space-y-4 lg:block">
          {extras.map(([label, value]) => (
            <div key={label}>
              <p className="text-xs font-semibold uppercase tracking-wide text-muted">{label}</p>
              <p className="whitespace-pre-line text-sm">{value}</p>
            </div>
          ))}
        </div>
      </section>

      {reel && (
        <section>
          <H>Reel</H>
          <Link href={`/post/${reel.id}`} className="group relative block aspect-video max-w-3xl overflow-hidden rounded-xl bg-surface">
            {reel.thumbnailUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={reel.thumbnailUrl} alt="" className="h-full w-full object-cover transition group-hover:scale-[1.02]" />
            )}
            <span className="absolute inset-0 flex items-center justify-center">
              <span className="flex h-16 w-16 items-center justify-center rounded-full bg-black/60 text-2xl text-white">▶</span>
            </span>
            <span className="absolute bottom-3 left-3 rounded-full bg-black/60 px-3 py-1 text-xs font-semibold text-white">{reel.title}</span>
            {(reel.duration || reel.videoUrl) && <Timecode seconds={reel.duration} src={reel.videoUrl} />}
          </Link>
        </section>
      )}

      <section>
        <H>Resume</H>
        {lines.length === 0 && (
          <p className="text-sm text-muted">{isOwn ? "Roles you're credited for on Nexus appear here. Add others with Edit." : "No credits yet."}</p>
        )}
        <div className="space-y-6">
          {categories.map((cat) => (
            <div key={cat}>
              <p className="mb-1 text-xs font-bold uppercase tracking-wider text-brand">{cat}</p>
              <table className="w-full text-sm">
                <tbody>
                  {lines
                    .filter((l) => l.category === cat)
                    .map((l, i) => (
                      <tr key={`${l.project}-${i}`} className="border-b border-border">
                        <td className="w-[38%] py-2 pr-3 font-semibold">
                          {l.href ? (
                            <Link href={l.href} className="hover:underline">
                              {l.project}
                            </Link>
                          ) : (
                            l.project
                          )}
                        </td>
                        <td className="w-[30%] py-2 pr-3">{l.role || "—"}</td>
                        <td className="py-2 text-right text-muted">{[l.company, l.year].filter(Boolean).join(", ")}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          ))}
        </div>
      </section>
    </>
  );
}

// MARK: - Filmmaker (IMDb)

function FilmmakerProfile({ creative, posts, person, isOwn }: { creative: CreativeProfile; posts: Post[]; person: Person; isOwn: boolean }) {
  const f = creative.details.filmmaker;
  const groups = new Map<string, { role: string; items: { post: Post; note: string }[] }>();
  // Screen work only: music credits belong on a musician's discography, not a filmography.
  for (const post of posts.filter((p) => p.category !== "music")) {
    for (const { group, credit } of creditsFor(post, person)) {
      const isCast = group === "Cast";
      const role = isCast ? "Actor" : credit.role.trim() || "Credited";
      const key = role.toLowerCase();
      const g = groups.get(key) ?? { role, items: [] };
      if (!g.items.some((x) => x.post.id === post.id)) g.items.push({ post, note: isCast && credit.role ? `as ${credit.role}` : "" });
      groups.set(key, g);
    }
  }
  const sorted = [...groups.values()]
    .map((g) => ({ ...g, items: [...g.items].sort((a, b) => (year(b.post) || "0").localeCompare(year(a.post) || "0")) }))
    .sort((a, b) => b.items.length - a.items.length || a.role.localeCompare(b.role));
  const stills = posts
    .filter((p) => p.category === "film" || p.category === "performance" || p.category === "photography" || p.category === "design")
    .flatMap((p) => (p.images?.length ? p.images.slice(0, 3) : p.thumbnailUrl ? [p.thumbnailUrl] : []).map((src) => ({ src, id: p.id })))
    .slice(0, 18);

  return (
    <>
      {(f.openToCrew || f.specialties || f.gear) && (
        <section className="space-y-1.5">
          {f.openToCrew && <span className="inline-block rounded-full bg-brand/15 px-3 py-1 text-xs font-semibold text-brand">Open to joining crews</span>}
          {f.specialties && <p className="text-sm">{f.specialties}</p>}
          {f.gear && <p className="text-sm text-muted">Gear: {f.gear}</p>}
        </section>
      )}

      <section>
        <H>Filmography</H>
        {sorted.length === 0 && <p className="text-sm text-muted">{isOwn ? "Everything you're credited on shows up here by job." : "No credits yet."}</p>}
        <div className="space-y-6">
          {sorted.map((g) => (
            <div key={g.role}>
              <p className="mb-1 flex items-baseline gap-2 border-b-2 border-brand pb-1">
                <span className="text-lg font-semibold">{g.role}</span>
                <span className="text-sm text-muted">
                  {g.items.length} credit{g.items.length === 1 ? "" : "s"}
                </span>
              </p>
              <ul>
                {g.items.map(({ post, note }) => (
                  <li key={post.id} className="flex items-baseline gap-4 border-b border-border py-2 text-sm">
                    <span className="w-12 shrink-0 tabular-nums text-muted">{year(post) || "—"}</span>
                    <span className="min-w-0">
                      <Link href={`/post/${post.id}`} className="font-semibold text-brand hover:underline">
                        {post.title}
                      </Link>
                      <span className="block text-xs text-muted">{[kind(post), note].filter(Boolean).join(" · ")}</span>
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      {stills.length > 0 && (
        <section>
          <H>Stills</H>
          <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-3 lg:grid-cols-4">
            {stills.map((s, i) => (
              <Link key={`${s.id}-${i}`} href={`/post/${s.id}`} className="block aspect-video overflow-hidden rounded bg-surface">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={s.src} alt="" loading="lazy" className="h-full w-full object-cover transition hover:scale-[1.03]" />
              </Link>
            ))}
          </div>
        </section>
      )}
    </>
  );
}

// MARK: - Musician (Spotify)

function MusicianProfile({
  creative,
  posts,
  person,
  events,
  isOwn,
}: {
  creative: CreativeProfile;
  posts: Post[];
  person: Person;
  events: NexusEvent[];
  isOwn: boolean;
}) {
  const m = creative.details.musician;
  const releases = posts
    .filter((p) => p.category === "music")
    .sort((a, b) => (year(b) || "0").localeCompare(year(a) || "0"));
  const isRecord = (p: Post) => /^(ep|album)$/i.test(p.details?.kindLabel ?? "");
  const songs = releases.filter((p) => !isRecord(p));
  const records = releases.filter(isRecord);
  const shows = upcomingShowsFor(events, person, m.artistName);
  const availability = musicianAvailability(m);
  const facts = [m.genres, m.instruments].filter(Boolean);

  return (
    <>
      {(m.artistName || facts.length > 0 || availability.length > 0) && (
        <section>
          {m.artistName && <p className="text-4xl font-black tracking-tight">{m.artistName}</p>}
          {facts.length > 0 && <p className="mt-1 text-muted">{facts.join(" · ")}</p>}
          {availability.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-1.5">
              {availability.map((x) => (
                <span key={x} className="rounded-full bg-brand/15 px-3 py-1 text-xs font-semibold text-brand">
                  Available: {x}
                </span>
              ))}
            </div>
          )}
        </section>
      )}

      {shows.length > 0 && (
        <section>
          <H>Upcoming shows</H>
          <ul className="space-y-2">
            {shows.map((e) => (
              <li key={e.id}>
                <Link href={`/discover/${e.id}`} className="flex items-center gap-4 rounded-xl p-2 hover:bg-surface">
                  <span className="w-14 shrink-0 text-center">
                    <span className="block text-xs font-bold uppercase text-brand">{e.startsAt ? dayFmt.format(e.startsAt).split(" ")[0] : ""}</span>
                    <span className="block text-2xl font-bold">{e.startsAt ? dayFmt.format(e.startsAt).split(" ")[1] : "—"}</span>
                  </span>
                  <span className="min-w-0">
                    <span className="block font-semibold">{e.title}</span>
                    <span className="block text-sm text-muted">{[e.location, e.startsAt ? timeFmt.format(e.startsAt) : e.when].filter(Boolean).join(" · ")}</span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section>
        <H>Songs</H>
        {songs.length === 0 && <p className="text-sm text-muted">{isOwn ? "Music you're credited on shows up here." : "No songs yet."}</p>}
        <ol>
          {songs.slice(0, 10).map((s, i) => (
            <li key={s.id}>
              <Link href={`/post/${s.id}`} className="group grid grid-cols-[1.5rem_3rem_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-surface">
                <span className="text-right text-sm tabular-nums text-muted group-hover:hidden">{i + 1}</span>
                <span className="hidden text-right text-sm group-hover:block">▶</span>
                {s.thumbnailUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={s.thumbnailUrl} alt="" className="h-12 w-12 rounded object-cover" />
                ) : (
                  <span className="h-12 w-12 rounded bg-surface" />
                )}
                <span className="min-w-0">
                  <span className="block truncate font-semibold">
                    {s.title}
                    {s.details?.explicit && <span className="ml-1.5 rounded-sm bg-foreground/20 px-1 text-[10px] font-bold">E</span>}
                  </span>
                  <span className="block truncate text-xs text-muted">{[s.details?.byline || s.creator, year(s)].filter(Boolean).join(" · ")}</span>
                </span>
                <span className="text-xs tabular-nums text-muted">
                  {s.duration ? `${Math.floor(s.duration / 60)}:${String(Math.round(s.duration % 60)).padStart(2, "0")}` : ""}
                </span>
              </Link>
            </li>
          ))}
        </ol>
      </section>

      {records.length > 0 && (
        <section>
          <H>Albums &amp; EPs</H>
          <div className="flex gap-4 overflow-x-auto pb-2">
            {records.map((r) => (
              <Link key={r.id} href={`/post/${r.id}`} className="w-40 shrink-0 rounded-lg p-2 hover:bg-surface">
                {r.thumbnailUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={r.thumbnailUrl} alt="" className="aspect-square w-full rounded-md object-cover shadow" />
                ) : (
                  <span className="block aspect-square w-full rounded-md bg-surface" />
                )}
                <span className="mt-2 block truncate text-sm font-semibold">{r.title}</span>
                <span className="block text-xs text-muted">{[year(r), r.details?.kindLabel].filter(Boolean).join(" · ")}</span>
              </Link>
            ))}
          </div>
        </section>
      )}
    </>
  );
}

