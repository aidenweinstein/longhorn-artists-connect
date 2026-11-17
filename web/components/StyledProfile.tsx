import Link from "next/link";
import { thumbSrc } from "@/lib/smallImage";
import PostLink from "./PostLink";
import Timecode from "./Timecode";
import type { Account } from "@/lib/cloudkit/content";
import type { NexusEvent } from "@/lib/discoverContent";
import type { Post } from "@/lib/mockContent";
import {
  actorStats,
  creditsFor,
  hasActorInfo,
  hasFilmmakerInfo,
  hasMusicianInfo,
  matchesPerson,
  PROFILE_STYLES,
  actNames,
  splitList,
  streamingLinks,
  emptyDetails,
  suggestedStyle,
  type CreativeProfile,
  type ProfileStyle,
} from "@/lib/profileStyle";

/*
 * The Actor Info, Filmmaker Info and Musician Info a person filled in under Edit
 * profile. It renders in two parts (the `part` prop):
 *   "info"  — a compact card per type, beside the details: Actor stats; Filmmaker studios,
 *             software and gear; Musician names, instruments, genres and streaming
 *             pages. Only cards with something filled in show, Actor always first.
 *   "lists" — reel and resume, filmography and stills, shows and songs, below the Work grid.
 * By type:
 *   Actor      — like Actors Access: headshot and skills, reel, typed-in resume.
 *   Filmmaker  — like IMDb: filmography grouped by job, newest first.
 *   Musician   — like Spotify: upcoming shows, songs, albums & EPs.
 * Their base profile type comes first and always shows in full; the other two show
 * once something is filled in, without their empty lists.
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
export function upcomingShowsFor(events: NexusEvent[], person: { name: string; profileID: string }, acts: string[] = []): NexusEvent[] {
  const now = Date.now() - 6 * 60 * 60 * 1000;
  const names = [person.name, ...acts].map((x) => x.trim().toLowerCase()).filter(Boolean);
  return events
    .filter((e) => (e.endsAt ?? e.startsAt ?? 0) >= now)
    .filter((e) => matchesPerson(e.postedBy ?? "", e.postedByProfileID, person) || (e.lineup ?? []).some((l) => names.some((n) => l.toLowerCase().includes(n))))
    .sort((a, b) => (a.startsAt ?? 0) - (b.startsAt ?? 0));
}

export default function StyledProfile({
  account,
  posts,
  creative,
  events,
  isOwn = false,
  part,
}: {
  account: Account;
  /** Posts this person is credited on. */
  posts: Post[];
  creative: CreativeProfile | null;
  /** Every Discover event, to find their upcoming shows. */
  events: NexusEvent[];
  isOwn?: boolean;
  /** "info" sits to the right of the details (under them on a narrow window); "lists" goes under the Work grid. */
  part: "info" | "lists";
}) {
  if (part === "info") return creative ? <InfoCards creative={creative} isOwn={isOwn} /> : null;

  // The lists show for everyone, including people who never filled in any Info:
  // filmography and songs come from what they're credited on, so they need no setup.
  const person = { name: account.name, profileID: account.profileID };
  const base = creative?.style ?? suggestedStyle(account.roles);
  const profile: CreativeProfile = creative ?? { userID: account.profileID, style: base ?? "Filmmaker", details: emptyDetails(), updatedAt: 0 };
  const d = profile.details;
  const has: Record<ProfileStyle, boolean> = {
    Actor: hasActorInfo(d.actor, profile.headshotUrl),
    Filmmaker: hasFilmmakerInfo(d.filmmaker) || posts.some((p) => p.category !== "music" && creditsFor(p, person).length > 0),
    Musician: hasMusicianInfo(d.musician) || posts.some((p) => p.category === "music"),
  };
  // Base type first (if they have one), then whichever others have something to show.
  const shown = [...(base ? [base] : []), ...PROFILE_STYLES.filter((s) => s !== base && has[s])];

  return (
    <>
      {shown.map((style) => {
        // Empty lists with "add this" hints only for a saved base type.
        const full = !!creative && style === creative.style;
        return (
          <div key={style} className="space-y-10 empty:hidden">
            {style === "Actor" && <ActorProfile creative={profile} posts={posts} person={person} isOwn={isOwn} name={account.name} full={full} />}
            {style === "Filmmaker" && <FilmmakerProfile posts={posts} person={person} isOwn={isOwn} full={full} />}
            {style === "Musician" && <MusicianProfile creative={profile} posts={posts} person={person} events={events} isOwn={isOwn} full={full} />}
          </div>
        );
      })}
    </>
  );
}

// MARK: - Info cards (beside the details)

function InfoCards({ creative, isOwn }: { creative: CreativeProfile; isOwn: boolean }) {
  const { actor, filmmaker, musician } = creative.details;
  const filled = (rows: [string, string][]) => rows.filter(([, v]) => v.trim()).map(([label, value]) => ({ label, value }));
  const links = streamingLinks(musician);
  const cards = [
    { style: "Actor", rows: actorStats(actor), links: [] },
    {
      style: "Filmmaker",
      rows: filled([
        ["Studio(s)", filmmaker.studios],
        ["Software", filmmaker.certifications],
        ["Gear", filmmaker.gear],
      ]),
      links: [],
    },
    {
      style: "Musician",
      rows: filled([
        ["Solo act", musician.soloName],
        ["Band", musician.bandName],
        ["Instruments", splitList(musician.instruments).join(", ")],
        ["Genres", splitList(musician.genres).join(", ")],
      ]),
      links,
    },
  ].filter((c) => c.rows.length > 0 || c.links.length > 0);
  if (cards.length === 0) return null;

  return (
    // Each card is only as wide as its text (w-fit), never the full column.
    <div className="flex flex-col items-start gap-2">
      {cards.map((c) => (
        <div key={c.style} className="w-fit max-w-full rounded-xl border border-border bg-surface/50 px-3.5 py-2.5">
          <div className="mb-1 flex items-center justify-between gap-6">
            <p className="text-xs font-semibold uppercase tracking-wider text-brand">{c.style}</p>
            {isOwn && (
              <Link href={`/portfolio/edit#${c.style.toLowerCase()}-info`} className="text-xs font-semibold text-muted hover:text-foreground">
                Edit
              </Link>
            )}
          </div>
          {c.rows.length > 0 && (
            <dl className="grid grid-cols-[auto_auto] justify-start gap-x-4 gap-y-0.5 text-sm">
              {c.rows.map((r) => (
                <div key={r.label} className="contents">
                  <dt className="text-muted">{r.label}</dt>
                  <dd className="whitespace-pre-line font-medium">{r.value}</dd>
                </div>
              ))}
            </dl>
          )}
          {c.links.length > 0 && (
            <div className="mt-2 flex flex-wrap gap-1.5">
              {c.links.map((l) => (
                <a
                  key={l.service}
                  href={l.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-full bg-brand px-3 py-1 text-xs font-semibold text-white hover:brightness-110"
                >
                  {l.service}
                </a>
              ))}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

type Person = { name: string; profileID: string };

// MARK: - Actor (Actors Access)

function ActorProfile({
  creative,
  posts,
  name,
}: {
  creative: CreativeProfile;
  posts: Post[];
  person: Person;
  isOwn: boolean;
  name: string;
  full: boolean;
}) {
  const a = creative.details.actor;
  const reel = a.reelPostID ? posts.find((p) => p.id === a.reelPostID) : undefined;

  // Resume: only the credits typed in under Edit profile. Nothing is added automatically.
  type Line = { category: string; project: string; role: string; company: string; year: string; href?: string };
  const lines: Line[] = [];
  for (const c of a.resume) lines.push({ category: c.category, project: c.project, role: c.role, company: c.company, year: c.year });
  const order = ["Film", "Television", "Theatre", "Performance", "Commercial", "New Media", "Other"];
  const categories = [
    ...order.filter((c) => lines.some((l) => l.category === c)),
    ...[...new Set(lines.map((l) => l.category))].filter((c) => !order.includes(c)),
  ];
  const extras = [
    ["Special skills", a.specialSkills],
    ["Languages", a.languages],
    ["Training", a.training],
  ].filter(([, v]) => v.trim());

  // The stats are on the Actor card beside the details; headshot and skills lead this section.
  return (
    <>
      {(creative.headshotUrl || extras.length > 0) && (
        <section className="flex gap-5">
          {creative.headshotUrl && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={creative.headshotUrl} alt={`${name} headshot`} className="aspect-[3/4] w-32 shrink-0 self-start rounded-lg object-cover" />
          )}
          {extras.length > 0 && (
            <div className="min-w-0 flex-1 space-y-3">
              {extras.map(([label, value]) => (
                <div key={label}>
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted">{label}</p>
                  <p className="whitespace-pre-line text-sm">{value}</p>
                </div>
              ))}
            </div>
          )}
        </section>
      )}
      {reel && (
        <section>
          <H>Reel</H>
          <PostLink postID={reel.id} mediaUrl={reel.videoUrl ?? reel.audioUrl} className="group relative block aspect-video max-w-3xl overflow-hidden rounded-xl bg-surface">
            {reel.thumbnailUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={thumbSrc(reel, 960)} alt="" className="h-full w-full object-cover transition group-hover:scale-[1.02]" />
            )}
            <span className="absolute inset-0 flex items-center justify-center">
              <span className="flex h-16 w-16 items-center justify-center rounded-full bg-black/60 text-2xl text-white">▶</span>
            </span>
            <span className="absolute bottom-3 left-3 rounded-full bg-black/60 px-3 py-1 text-xs font-semibold text-white">{reel.title}</span>
            {(reel.duration || reel.videoUrl) && <Timecode seconds={reel.duration} src={reel.videoUrl} />}
          </PostLink>
        </section>
      )}

      {lines.length > 0 && (
        <section>
          <H>Resume</H>
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
      )}
    </>
  );
}

// MARK: - Filmmaker (IMDb)

function FilmmakerProfile({
  posts,
  person,
  isOwn,
  full,
}: {
  posts: Post[];
  person: Person;
  isOwn: boolean;
  full: boolean;
}) {
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

  return (
    <>
      {(full || sorted.length > 0) && (
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
                        <PostLink postID={post.id} mediaUrl={post.videoUrl ?? post.audioUrl} className="font-semibold text-brand hover:underline">
                          {post.title}
                        </PostLink>
                        <span className="block text-xs text-muted">{[kind(post), note].filter(Boolean).join(" · ")}</span>
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
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
  full,
}: {
  creative: CreativeProfile;
  posts: Post[];
  person: Person;
  events: NexusEvent[];
  isOwn: boolean;
  full: boolean;
}) {
  const m = creative.details.musician;
  const releases = posts.filter((p) => p.category === "music").sort((a, b) => (year(b) || "0").localeCompare(year(a) || "0"));
  const isRecord = (p: Post) => /^(ep|album)$/i.test(p.details?.kindLabel ?? "");
  const songs = releases.filter((p) => !isRecord(p));
  const records = releases.filter(isRecord);
  const shows = upcomingShowsFor(events, person, actNames(m));

  return (
    <>
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
                    <span className="block text-sm text-muted">
                      {[e.location, e.startsAt ? timeFmt.format(e.startsAt) : e.when].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {(full || songs.length > 0) && (
        <section>
          <H>Songs</H>
          {songs.length === 0 && <p className="text-sm text-muted">{isOwn ? "Music you're credited on shows up here." : "No songs yet."}</p>}
          <ol>
            {songs.slice(0, 10).map((s, i) => (
              <li key={s.id}>
                <PostLink postID={s.id} mediaUrl={s.videoUrl ?? s.audioUrl}
                  className="group grid grid-cols-[1.5rem_3rem_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-surface"
                >
                  <span className="text-right text-sm tabular-nums text-muted group-hover:hidden">{i + 1}</span>
                  <span className="hidden text-right text-sm group-hover:block">▶</span>
                  {s.thumbnailUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={thumbSrc(s)} alt="" className="h-12 w-12 rounded object-cover" />
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
                </PostLink>
              </li>
            ))}
          </ol>
        </section>
      )}

      {records.length > 0 && (
        <section>
          <H>Albums &amp; EPs</H>
          <div className="flex gap-4 overflow-x-auto pb-2">
            {records.map((r) => (
              <PostLink key={r.id} postID={r.id} mediaUrl={r.videoUrl ?? r.audioUrl} className="w-40 shrink-0 rounded-lg p-2 hover:bg-surface">
                {r.thumbnailUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={thumbSrc(r)} alt="" className="aspect-square w-full rounded-md object-cover shadow" />
                ) : (
                  <span className="block aspect-square w-full rounded-md bg-surface" />
                )}
                <span className="mt-2 block truncate text-sm font-semibold">{r.title}</span>
                <span className="block text-xs text-muted">{[year(r), r.details?.kindLabel].filter(Boolean).join(" · ")}</span>
              </PostLink>
            ))}
          </div>
        </section>
      )}
    </>
  );
}
