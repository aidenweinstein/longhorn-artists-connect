import Link from "next/link";
import { AuditionButton, AuditionStatusSelect, StylePicker } from "@/components/NowActions";
import { Group, Section } from "@/components/NowTabs";
import { currentAccount } from "@/lib/account";
import { discoverItems } from "@/lib/content";
import type { DiscoverItem, NexusEvent, Project } from "@/lib/discoverContent";
import { allListings } from "@/lib/cloudkit/creative";
import { myStyle } from "@/lib/myStyle";
import {
  GIG_PATTERN,
  STYLE_INFO,
  crewFor,
  emptyDetails,
  fitsRole,
  isMusicRole,
  matchesPerson,
  parseRole,
  roleChips,
  suggestedStyle,
} from "@/lib/profileStyle";

// Depends on who's signed in and on live projects, so it renders per request.
export const instant = false;

const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "America/Chicago" });
const eventFmt = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Chicago" });

const STAGE: Record<Project["projectType"], string> = {
  "Cast & Crew Call": "Crewing up",
  "In Development": "In development",
  Script: "Script",
};

/**
 * What's happening now, shaped by the visitor's base profile style:
 *   Actor      — shoots you're cast in, auditions you've logged, roles that fit you.
 *   Filmmaker  — your projects in production, and crews looking for your role tags.
 *   Musician   — your upcoming shows, composer openings, and gigs, open mics and jams.
 */
export default async function NowPage() {
  const current = await currentAccount().catch(() => null);
  if (!current) {
    return (
      <div className="w-full">
        <h1 className="text-3xl">Now</h1>
        <p className="mt-1 text-muted">Your sets, auditions and shows, and what you could get on next.</p>
        <Link href="/signin" className="mt-6 inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          Sign in
        </Link>
      </div>
    );
  }

  const [{ style, profile }, items, listings] = await Promise.all([myStyle(), discoverItems().catch((): DiscoverItem[] => []), allListings()]);
  const account = current.account;

  if (!style) {
    return (
      <div className="w-full">
        <h1 className="text-3xl">Now</h1>
        <StylePicker suggested={suggestedStyle(account?.roles ?? [])} />
      </div>
    );
  }

  const me = { name: account?.name ?? "", profileID: account?.profileID ?? "" };
  const details = profile?.details ?? emptyDetails();
  const tags = account?.roles ?? [];
  const projects = items.filter((i): i is Project => i.kind === "project");
  const events = items.filter((i): i is NexusEvent => i.kind === "event");
  const isMine = (p: Project) => !!me.name && matchesPerson(p.postedBy, p.postedByProfileID, me);
  const openCalls = projects.filter((p) => p.projectType === "Cast & Crew Call" && !isMine(p));
  const upcoming = upcomingEvents(events);

  const listing = account && profile ? listings.get(profile.userID) : undefined;
  const status = !account
    ? "Link this email to your Nexus app account to save your style and appear on the public pages."
    : listing?.style === style && listing.status === "approved"
      ? `Listed on the ${STYLE_INFO[style].plural} page`
      : listing?.style === style && listing.status === "declined"
        ? `Not listed on the ${STYLE_INFO[style].plural} page. Edit your profile to send it back for review.`
        : `Waiting for a moderator to add you to the ${STYLE_INFO[style].plural} page`;

  return (
    <div className="w-full">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl">Now</h1>
          <p className="mt-1 text-muted">
            {style} profile · {status}
          </p>
        </div>
        <Link href="/portfolio/style" className="rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-surface">
          Edit profile style
        </Link>
      </header>

      {style === "Actor" && <Acting projects={projects} openCalls={openCalls} me={me} details={details} />}
      {style === "Filmmaker" && <Filmmaking projects={projects} openCalls={openCalls} me={me} tags={tags} />}
      {style === "Musician" && <Music openCalls={openCalls} upcoming={upcoming} me={me} artistName={details.musician.artistName} />}
    </div>
  );
}

type Me = { name: string; profileID: string };

/** Events still to come (or on today), soonest first. */
function upcomingEvents(events: NexusEvent[]): NexusEvent[] {
  const cutoff = Date.now() - 6 * 60 * 60 * 1000;
  return events.filter((e) => (e.endsAt ?? e.startsAt ?? 0) >= cutoff).sort((a, b) => (a.startsAt ?? 0) - (b.startsAt ?? 0));
}

function Empty({ children }: { children: React.ReactNode }) {
  return <p className="text-sm text-muted">{children}</p>;
}

function Chips({ chips }: { chips: string[] }) {
  if (!chips.length) return null;
  return (
    <div className="mt-2 flex flex-wrap gap-1">
      {chips.map((c, i) => (
        <span key={`${c}-${i}`} className="rounded-full bg-brand/15 px-2 py-0.5 text-[11px] font-medium text-brand">
          {c}
        </span>
      ))}
    </div>
  );
}

function ProjectRow({ project, children, chips = [], aside }: { project: Project; children?: React.ReactNode; chips?: string[]; aside?: React.ReactNode }) {
  return (
    <article className="grid gap-4 rounded-xl border border-border p-4 sm:grid-cols-[4rem_minmax(0,1fr)_auto] sm:items-center">
      <Link href={`/discover/${project.id}`} className="hidden aspect-[2/3] w-16 overflow-hidden rounded bg-surface sm:block">
        {project.posterUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={project.posterUrl} alt="" className="h-full w-full object-cover" />
        )}
      </Link>
      <div className="min-w-0">
        <Link href={`/discover/${project.id}`} className="font-display text-lg leading-tight hover:underline">
          {project.title}
        </Link>
        {project.logline && <p className="mt-0.5 line-clamp-2 text-sm text-muted">{project.logline}</p>}
        {children}
        <Chips chips={chips} />
      </div>
      {aside}
    </article>
  );
}

// MARK: - Actor

function Acting({ projects, openCalls, me, details }: { projects: Project[]; openCalls: Project[]; me: Me; details: ReturnType<typeof emptyDetails> }) {
  const actor = details.actor;
  const shooting = projects.filter((p) => (p.castAssembled ?? []).some((c) => matchesPerson(c.name, c.profileID, me)));
  const cast = (p: Project) => (p.castAssembled ?? []).some((c) => matchesPerson(c.name, c.profileID, me));
  const roles = openCalls.flatMap((project) =>
    project.castNeeded
      .map((w) => w.trim())
      .filter(Boolean)
      .map((role) => ({ project, role, req: parseRole(role) }))
      .filter((r) => fitsRole(r.req, actor)),
  );
  const done = new Set(details.auditions.map((a) => `${a.projectID}|${a.role}`));
  const basics = (actor.ageMin !== undefined || actor.ageMax !== undefined) && !!actor.gender;

  return (
    <Group title="Acting">
      {shooting.length > 0 && (
        <Section title="Shooting" count={shooting.length || undefined}>
          <div className="space-y-3">
            {shooting.map((p) => {
              const role = (p.castAssembled ?? []).find((c) => matchesPerson(c.name, c.profileID, me))?.role;
              return (
                <ProjectRow key={p.id} project={p}>
                  <p className="mt-1 text-sm">
                    <span className="text-muted">Your role: </span>
                    <span className="font-semibold">{role || "Cast"}</span>
                    {p.shootDates && <span className="text-muted"> · Shoots {p.shootDates}</span>}
                  </p>
                </ProjectRow>
              );
            })}
          </div>
        </Section>
      )}

      <Section title="Your auditions" count={details.auditions.length || undefined}>
        {details.auditions.length === 0 ? (
          <Empty>Roles you audition for below are tracked here.</Empty>
        ) : (
          <div className="overflow-hidden rounded-xl border border-border">
            {details.auditions.map((a, i) => {
              const project = projects.find((p) => p.id === a.projectID);
              return (
                <div key={a.id} className={`grid gap-2 p-3 text-sm sm:grid-cols-[7rem_minmax(0,1.2fr)_minmax(0,1fr)_auto] sm:items-center ${i ? "border-t border-border" : ""}`}>
                  <span className="font-semibold">{dateFmt.format(a.date)}</span>
                  <span className="font-semibold">
                    {project ? (
                      <Link href={`/discover/${project.id}`} className="hover:underline">
                        {a.projectTitle}
                      </Link>
                    ) : (
                      a.projectTitle
                    )}
                  </span>
                  <span>
                    <span className="text-muted">Role: </span>
                    {a.role}
                  </span>
                  <AuditionStatusSelect id={a.id} status={a.status} booked={!!project && cast(project)} />
                </div>
              );
            })}
          </div>
        )}
      </Section>

      <Section title="Roles you could audition for" count={roles.length || undefined}>
        {!basics && (
          <p className="mb-3 text-sm">
            <Link href="/portfolio/style" className="font-semibold text-brand hover:underline">
              Add your age range and gender
            </Link>{" "}
            <span className="text-muted">so these fit you.</span>
          </p>
        )}
        {roles.length === 0 ? (
          <Empty>No open roles fit your profile right now.</Empty>
        ) : (
          <div className="space-y-3">
            {roles.map(({ project, role, req }) => (
              <ProjectRow
                key={`${project.id}-${role}`}
                project={project}
                chips={roleChips(req)}
                aside={<AuditionButton projectID={project.id} projectTitle={project.title} role={role} done={done.has(`${project.id}|${role}`)} />}
              >
                <p className="mt-1 text-sm">
                  <span className="font-semibold">{role}</span>
                  {project.shootDates && <span className="text-muted"> · Shoots {project.shootDates}</span>}
                </p>
              </ProjectRow>
            ))}
          </div>
        )}
      </Section>
    </Group>
  );
}

// MARK: - Filmmaker

function Filmmaking({ projects, openCalls, me, tags }: { projects: Project[]; openCalls: Project[]; me: Me; tags: string[] }) {
  const roleOn = (p: Project) =>
    [...(p.crewAssembled ?? []), ...(p.castAssembled ?? [])].filter((c) => matchesPerson(c.name, c.profileID, me)).map((c) => c.role).filter(Boolean);
  // Only projects you're credited on (cast or crew); posting a project alone doesn't count.
  const mine = projects.filter((p) => roleOn(p).length > 0);
  const openings = openCalls.map((project) => ({ project, roles: crewFor(project.crewNeeded, tags) })).filter((o) => o.roles.length > 0);

  return (
    <Group title="Filmmaking">
      <Section title="In production" count={mine.length || undefined}>
        {mine.length === 0 ? (
          <Empty>Projects you&rsquo;re credited on in the app show up here.</Empty>
        ) : (
          <div className="space-y-3">
            {mine.map((p) => (
              <ProjectRow
                key={p.id}
                project={p}
                aside={<span className="w-fit rounded-full bg-brand/15 px-2.5 py-0.5 text-[11px] font-semibold text-brand">{STAGE[p.projectType]}</span>}
              >
                <p className="mt-1 text-sm">
                  <span className="text-muted">Your role: </span>
                  <span className="font-semibold">{roleOn(p).join(", ")}</span>
                  {p.shootDates && <span className="text-muted"> · Shoots {p.shootDates}</span>}
                </p>
              </ProjectRow>
            ))}
          </div>
        )}
      </Section>

      <Section title="Crews you could join" count={openings.length || undefined}>
        {tags.length === 0 && (
          <p className="mb-3 text-sm">
            <Link href="/portfolio/edit" className="font-semibold text-brand hover:underline">
              Add role tags
            </Link>{" "}
            <span className="text-muted">to see only the jobs you do.</span>
          </p>
        )}
        {openings.length === 0 ? (
          <Empty>No crews are looking for your roles right now.</Empty>
        ) : (
          <div className="space-y-3">
            {openings.map(({ project, roles }) => (
              <ProjectRow
                key={project.id}
                project={project}
                chips={roles}
                aside={
                  <Link href={`/discover/${project.id}`} className="rounded-full bg-brand px-4 py-1.5 text-xs font-semibold text-white hover:brightness-110">
                    View project
                  </Link>
                }
              >
                <p className="mt-1 text-xs text-muted">
                  Posted by {project.postedBy}
                  {project.shootDates && ` · Shoots ${project.shootDates}`}
                </p>
              </ProjectRow>
            ))}
          </div>
        )}
      </Section>
    </Group>
  );
}

// MARK: - Musician

function EventRow({ event }: { event: NexusEvent }) {
  return (
    <Link href={`/discover/${event.id}`} className="grid gap-3 rounded-xl border border-border p-4 hover:bg-surface sm:grid-cols-[4rem_minmax(0,1fr)] sm:items-center">
      <span className="hidden aspect-square w-16 overflow-hidden rounded bg-surface sm:block">
        {event.flyerUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={event.flyerUrl} alt="" className="h-full w-full object-cover" />
        )}
      </span>
      <span className="min-w-0">
        <span className="block font-display text-lg leading-tight">{event.title}</span>
        <span className="block text-sm text-muted">
          {[event.category, event.location, event.startsAt ? eventFmt.format(event.startsAt) : event.when].filter(Boolean).join(" · ")}
        </span>
      </span>
    </Link>
  );
}

function Music({ openCalls, upcoming, me, artistName }: { openCalls: Project[]; upcoming: NexusEvent[]; me: Me; artistName: string }) {
  const names = [me.name, artistName].map((n) => n.trim().toLowerCase()).filter(Boolean);
  const shows = upcoming.filter(
    (e) =>
      (!!me.name && matchesPerson(e.postedBy ?? "", e.postedByProfileID, me)) ||
      (e.lineup ?? []).some((l) => names.some((n) => l.toLowerCase().includes(n))),
  );
  const showIDs = new Set(shows.map((s) => s.id));
  const composer = openCalls
    .map((project) => ({ project, roles: [...project.crewNeeded, ...project.castNeeded].map((r) => r.trim()).filter(isMusicRole) }))
    .filter((o) => o.roles.length > 0);
  const gigs = upcoming.filter(
    (e) =>
      !showIDs.has(e.id) &&
      (e.category === "Concert" || e.category === "Artist Mixer" || GIG_PATTERN.test(`${e.title} ${e.logline}`.toLowerCase())),
  );

  return (
    <Group title="Music">
      <Section title="Your upcoming shows" count={shows.length || undefined}>
        {shows.length === 0 ? (
          <Empty>Events you post or are in the lineup for show up here and on your profile.</Empty>
        ) : (
          <div className="space-y-3">
            {shows.map((e) => (
              <EventRow key={e.id} event={e} />
            ))}
          </div>
        )}
      </Section>

      <Section title="Composer openings" count={composer.length || undefined}>
        {composer.length === 0 ? (
          <Empty>No projects are looking for a composer right now.</Empty>
        ) : (
          <div className="space-y-3">
            {composer.map(({ project, roles }) => (
              <ProjectRow key={project.id} project={project} chips={roles}>
                <p className="mt-1 text-xs text-muted">
                  Posted by {project.postedBy}
                  {project.releaseDate && ` · Release ${project.releaseDate}`}
                </p>
              </ProjectRow>
            ))}
          </div>
        )}
      </Section>

      <Section title="Gigs, open mics & jams" count={gigs.length || undefined}>
        {gigs.length === 0 ? (
          <Empty>No upcoming gigs, open mics or jam sessions yet.</Empty>
        ) : (
          <div className="space-y-3">
            {gigs.map((e) => (
              <EventRow key={e.id} event={e} />
            ))}
          </div>
        )}
      </Section>
    </Group>
  );
}
