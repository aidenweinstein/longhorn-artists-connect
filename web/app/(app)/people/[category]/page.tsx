import Link from "next/link";
import { notFound } from "next/navigation";
import Headshot from "@/components/Headshot";
import PersonLink from "@/components/PersonLink";
import { currentSession, personAccount } from "@/lib/account";
import WorkStatusPill from "@/components/WorkStatusPill";
import { PEOPLE_PAGES, featuresFor, isAdmin, peoplePage, type Feature, type PeopleSlug } from "@/lib/featured";
import { sampleCreative, samplesFor, type SampleProfile } from "@/lib/sampleProfiles";
import { SAMPLE_CASTING_CALL, fitsRole } from "@/lib/castingCalls";
import { allCreativeProfiles, allListings, getCreativeProfile } from "@/lib/cloudkit/creative";
import { styleForSlug } from "@/lib/profileStyle";

// Who's featured can change at any moment from the admin page, so this renders per request.
export const instant = false;

export function generateStaticParams() {
  return PEOPLE_PAGES.map((p) => ({ category: p.slug }));
}

export default async function PeoplePage(props: PageProps<"/people/[category]">) {
  const { category } = await props.params;
  const page = peoplePage(category);
  if (!page) notFound();

  const [features, session, listings, creatives] = await Promise.all([
    featuresFor(page.slug),
    currentSession(),
    allListings(),
    allCreativeProfiles(),
  ]);
  // People a moderator approved from the app (DirectoryListing) who aren't featured here yet.
  const style = styleForSlug(page.slug);
  const featuredIDs = new Set(features.map((f) => f.profileID.replace(/^UserProfile_/, "")));
  const listed = [...listings.values()]
    .filter((l) => l.status === "approved" && l.style === style && creatives.get(l.userID)?.style === style && !featuredIDs.has(l.userID))
    .map((l) => ({ id: l.userID, profileID: `UserProfile_${l.userID}`, name: "", blurb: "", category: page.slug, postIDs: [] }));
  const viewerSchool = session?.schoolName ?? "";
  const allSamples = samplesFor(page.slug);

  // Actors open filtered to the first role in the upcoming film; ?role=all shows everyone.
  const casting = page.slug === "actors" ? SAMPLE_CASTING_CALL : null;
  const roleParam = (await props.searchParams).role;
  const wanted = typeof roleParam === "string" ? roleParam : undefined;
  const role = casting && wanted !== "all" ? (casting.roles.find((r) => r.slug === wanted) ?? casting.roles[0]) : undefined;
  const samples = role ? allSamples.filter((p) => fitsRole(p, role)) : allSamples;

  return (
    <div className="w-full">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">{page.label}</h1>
          <p className="mt-1 text-muted">Hand-picked {page.label.toLowerCase()} from the Nexus community.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            href={`/people/${page.slug}/sample`}
            className="rounded-full border border-border px-5 py-2 text-sm font-semibold hover:bg-surface"
          >
            View sample portfolio
          </Link>
          {isAdmin(session) && (
            <Link href="/admin/people" className="rounded-full border border-border px-5 py-2 text-sm font-semibold hover:bg-surface">
              Manage
            </Link>
          )}
        </div>
      </header>

      {casting && (
        <section className="mt-5 rounded-xl border border-border p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-muted">Casting for your upcoming film</p>
          <h2 className="mt-1 text-xl">{casting.project}</h2>
          <p className="mt-0.5 text-sm text-muted">{casting.logline}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            {casting.roles.map((r) => (
              <Link
                key={r.slug}
                href={`/people/actors?role=${r.slug}`}
                scroll={false}
                className={`rounded-full px-4 py-1.5 text-sm font-semibold ${
                  role?.slug === r.slug ? "bg-brand text-white" : "border border-border hover:bg-surface"
                }`}
              >
                {r.name}
              </Link>
            ))}
            <Link
              href="/people/actors?role=all"
              scroll={false}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold ${!role ? "bg-foreground text-background" : "border border-border hover:bg-surface"}`}
            >
              All actors
            </Link>
          </div>
          {role && (
            <p className="mt-3 text-sm">
              <span className="font-semibold">{role.name}:</span> <span className="text-foreground/85">{role.description}</span>
              <span className="mt-1 block text-xs text-muted">
                {[
                  role.gender,
                  role.ageMin !== undefined || role.ageMax !== undefined ? `Ages ${role.ageMin ?? "?"}–${role.ageMax ?? "?"}` : "",
                  role.ethnicAppearance?.length ? `Appearance: ${role.ethnicAppearance.join(" / ")}` : "",
                  role.skills?.length ? `Must have: ${role.skills.join(", ")}` : "",
                ]
                  .filter(Boolean)
                  .join(" · ")}
                {" · "}
                {samples.length} {samples.length === 1 ? "actor fits" : "actors fit"}
              </span>
            </p>
          )}
        </section>
      )}

      {role && samples.length === 0 && features.length === 0 && (
        <p className="py-16 text-center text-muted">No featured actors fit {role.name} yet.</p>
      )}

      {features.length + listed.length > 0 && (
        <div className="mt-6 grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {[...features, ...listed].map((f) => (
            <FeaturedPerson key={f.id} feature={f} kind={page.slug} viewerSchool={viewerSchool} />
          ))}
        </div>
      )}

      {features.length + listed.length === 0 && allSamples.length === 0 && (
        <p className="py-24 text-center text-muted">No one featured here yet.</p>
      )}

      {samples.length > 0 && (
        <div className="mt-6">
          {features.length > 0 && <p className="pt-2 text-xs font-semibold uppercase tracking-wider text-muted">Samples</p>}
          <div className="grid grid-cols-2 gap-x-4 gap-y-8 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {samples.map((p) => (
              <SamplePerson key={p.id} profile={p} viewerSchool={viewerSchool} />
            ))}
          </div>
        </div>
      )}

    </div>
  );
}

const SAMPLE_TAG = (
  <span className="rounded-full border border-border px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted">
    Sample
  </span>
);

/** "The University of Texas at Austin" and "University of Texas at Austin" are the same school. */
function sameSchool(a: string, b: string) {
  const norm = (s: string) => s.toLowerCase().replace(/^the\s+/, "").replace(/[^a-z0-9]/g, "");
  return !!a && !!b && norm(a) === norm(b);
}

type CardProps = {
  name: string;
  profileID?: string;
  photo?: string;
  major?: string;
  classOf?: string;
  /** Pros have no major or class; this line stands in. */
  academicLine?: string;
  school?: string;
  viewerSchool: string;
  status?: string;
  sampleTag?: boolean;
};

/**
 * One person on a People page: their picture, then name, major and class, then their
 * status (Available to Work / Busy). Everything else is on their portfolio, a click away.
 */
function PersonCard(c: CardProps) {
  return (
    <article className="flex flex-col">
      <PersonLink name={c.name} profileID={c.profileID} className="no-underline">
        <Headshot name={c.name} src={c.photo} />
      </PersonLink>
      <h2 className="mt-3 break-words text-lg font-semibold leading-tight">
        <PersonLink name={c.name} profileID={c.profileID}>
          {c.name}
        </PersonLink>
      </h2>
      {c.major || c.classOf ? (
        <div className="mt-0.5 text-sm text-muted">
          {c.major && <p>{c.major}</p>}
          {c.classOf && <p>Class of {c.classOf}</p>}
        </div>
      ) : (
        c.academicLine && <p className="mt-0.5 text-sm text-muted">{c.academicLine}</p>
      )}
      {c.school && !sameSchool(c.school, c.viewerSchool) && <p className="text-sm font-medium">{c.school}</p>}
      {(c.status || c.sampleTag) && (
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <WorkStatusPill status={c.status} />
          {c.sampleTag && SAMPLE_TAG}
        </div>
      )}
    </article>
  );
}

async function FeaturedPerson({ feature, kind, viewerSchool }: { feature: Feature; kind: PeopleSlug; viewerSchool: string }) {
  const [account, creative] = await Promise.all([
    personAccount(feature.profileID).catch(() => null),
    // Actors show their headshot when they've added one.
    kind === "actors" && feature.profileID ? getCreativeProfile(feature.profileID) : Promise.resolve(null),
  ]);
  const name = account?.name || feature.name;
  if (!name) return null;
  return (
    <PersonCard
      name={name}
      profileID={feature.profileID}
      photo={creative?.headshotUrl || account?.imageUrl}
      major={account?.major}
      classOf={account?.classOf}
      academicLine={account?.academicLine}
      school={account?.school}
      viewerSchool={viewerSchool}
      status={account?.workStatus}
    />
  );
}

/** A placeholder profile from lib/sampleProfiles.ts. */
function SamplePerson({ profile, viewerSchool }: { profile: SampleProfile; viewerSchool: string }) {
  return (
    <PersonCard
      name={profile.name}
      // Actor samples open a full sample profile; the others aren't clickable.
      profileID={sampleCreative(profile) ? profile.id : undefined}
      photo={profile.headshot}
      major={profile.major}
      classOf={profile.classOf}
      school={profile.school}
      viewerSchool={viewerSchool}
      status={profile.workStatus}
      sampleTag={profile.sample}
    />
  );
}
