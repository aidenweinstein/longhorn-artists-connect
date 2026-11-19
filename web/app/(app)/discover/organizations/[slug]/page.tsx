import type { ReactNode } from "react";
import { thumbSrc } from "@/lib/smallImage";
import Link from "next/link";
import { notFound } from "next/navigation";
import PostLink from "@/components/PostLink";
import { discoverItems, feedPosts, organizations, orgLinks } from "@/lib/content";
import type { NexusEvent } from "@/lib/discoverContent";
import { eventStart } from "@/lib/eventTimes";
import type { Post } from "@/lib/mockContent";
import {
  COLLECTIVE_SEASONS,
  ORGANIZATIONS,
  SECTION_TITLES,
  catalogTitles,
  normalizeTitle,
  type OrgSection,
} from "@/lib/organizations";

// One organization's page, mirroring the app's OrganizationPageView: picture, name,
// description, then its sections. Hardcoded catalogs (Collective's Weekly Shorts and
// projects, Incubator's pilots) match real posts by title; other sections show the
// posts moderators added in the app; events are the ones that credit the org as host.

// Reads the address and live data per request, so this route blocks until it renders.
export const instant = false;

export function generateStaticParams() {
  return ORGANIZATIONS.map((o) => ({ slug: o.slug }));
}

const TYPE_LABEL: Record<Post["category"], string> = {
  film: "Film",
  music: "Music",
  performance: "Performance",
  photography: "Photography",
  design: "Design",
};

function Row({ thumb, title, note, dim }: { thumb?: string; title: string; note: string; dim?: boolean }) {
  return (
    <div
      className={`flex items-center gap-3 rounded-xl p-2.5 ${dim ? "opacity-60" : "transition hover:brightness-110"}`}
      style={{ backgroundColor: `color-mix(in srgb, currentColor ${dim ? 6 : 12}%, transparent)` }}
    >
      <div
        className="h-[58px] w-24 shrink-0 overflow-hidden rounded-lg"
        style={{ backgroundColor: "color-mix(in srgb, currentColor 10%, transparent)" }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {thumb && <img src={thumb} alt="" loading="lazy" className="h-full w-full object-cover" />}
      </div>
      <div className="min-w-0">
        <p className="line-clamp-2 font-semibold leading-snug">{title}</p>
        <p className="text-sm opacity-75">{note}</p>
      </div>
    </div>
  );
}

function PostRow({ post, title }: { post: Post; title?: string }) {
  return (
    <PostLink postID={post.id} mediaUrl={post.videoUrl ?? post.audioUrl} className="block">
      <Row thumb={thumbSrc(post) ?? post.images?.[0]} title={title ?? post.title} note={TYPE_LABEL[post.category]} />
    </PostLink>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2.5 text-2xl font-bold">{title}</h2>
      <div className="grid gap-2.5 sm:grid-cols-2">{children}</div>
    </section>
  );
}

const Empty = () => <p className="text-sm opacity-60">Nothing here yet.</p>;

/** Sort key for newest-first ordering: the start time, with undated events (start = Infinity) pushed to the end. */
function newestFirstKey(e: NexusEvent) {
  const start = eventStart(e);
  return Number.isFinite(start) ? start : Number.MIN_SAFE_INTEGER;
}

function EventRow({ e }: { e: NexusEvent }) {
  return (
    <Link href={`/discover/${e.id}`} className="block">
      <Row thumb={e.flyerSmallUrl ?? e.flyerUrl} title={e.title} note={[e.when, e.location].filter(Boolean).join(" · ") || "Event"} />
    </Link>
  );
}

export default async function OrganizationPage(props: PageProps<"/discover/organizations/[slug]">) {
  const { slug } = await props.params;
  const [orgs, posts, links, items] = await Promise.all([organizations(), feedPosts(), orgLinks(), discoverItems()]);
  const org = orgs.find((o) => o.slug === slug);
  if (!org) notFound();

  const byTitle = new Map<string, Post>();
  for (const p of posts) if (!byTitle.has(normalizeTitle(p.title))) byTitle.set(normalizeTitle(p.title), p);
  const byID = new Map(posts.map((p) => [p.id.toUpperCase(), p]));
  const mine = links.filter((l) => l.orgSlug === org.slug);

  const events = items
    .filter((i): i is NexusEvent => i.kind === "event" && i.host.trim().toLowerCase() === org.name.toLowerCase())
    // Newest first (latest start date at the top); undated events last.
    .sort((a, b) => newestFirstKey(b) - newestFirstKey(a));

  /** A catalog title as a row: a link once it's been posted, a dimmed "Not posted yet" until then. */
  const catalogRow = (title: string, label = title) => {
    const post = byTitle.get(normalizeTitle(title));
    return post ? <PostRow key={title} post={post} title={label} /> : <Row key={title} title={label} note="Not posted yet" dim />;
  };

  const linked = (section: OrgSection, season?: string) =>
    mine
      .filter((l) => l.section === section && (season === undefined || l.season === season))
      .flatMap((l) => (byID.has(l.postID) ? [byID.get(l.postID)!] : []));

  function sectionBody(section: OrgSection): ReactNode {
    if (section === "events") {
      return events.length ? <Section title="Events">{events.map((e) => <EventRow key={e.id} e={e} />)}</Section> : <Section title="Events"><Empty /></Section>;
    }
    if (section === "weeklyShortSeasons") {
      if (org!.slug === "collective") {
        return COLLECTIVE_SEASONS.map(({ season, titles }) => (
          <Section key={season} title={`Weekly Shorts · Season ${season}`}>
            {titles.map((t, i) => catalogRow(t, `S${season}E${i + 1}  ${t}`))}
          </Section>
        ));
      }
      const seasons = [...new Set(mine.filter((l) => l.section === section).map((l) => l.season))].sort(
        (a, b) => Number(a === "") - Number(b === "") || a.localeCompare(b),
      );
      if (!seasons.length) return <Section title={SECTION_TITLES[section]}><Empty /></Section>;
      return seasons.map((s) => (
        <Section key={s} title={`Weekly Shorts · ${s || "Miscellaneous"}`}>
          {linked(section, s).map((p) => <PostRow key={p.id} post={p} />)}
        </Section>
      ));
    }
    const titles = catalogTitles(org!.slug, section);
    const rows = titles.length ? titles.map((t) => catalogRow(t)) : linked(section).map((p) => <PostRow key={p.id} post={p} />);
    return <Section title={SECTION_TITLES[section]}>{rows.length ? rows : <Empty />}</Section>;
  }

  return (
    <div style={{ backgroundColor: org.background, color: org.text }} className="-mx-3 -mb-6 -mt-3 min-h-full px-5 py-6 sm:px-8">
      <div className="mx-auto max-w-5xl space-y-6">
        <Link href="/discover/organizations" className="text-sm font-medium opacity-80 hover:opacity-100">
          ← All organizations
        </Link>
        <header className="flex items-center gap-4">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={org.imageUrl} alt="" className="h-[84px] w-[84px] shrink-0 rounded-full object-cover" />
          <h1 className="text-4xl font-bold leading-tight">{org.name}</h1>
        </header>
        {org.description && <p className="opacity-85">{org.description}</p>}
        {org.sections.map((s) => (
          <div key={s} className="space-y-6">{sectionBody(s)}</div>
        ))}
        {!org.sections.includes("events") && events.length > 0 && (
          <Section title="Events">{events.map((e) => <EventRow key={e.id} e={e} />)}</Section>
        )}
      </div>
    </div>
  );
}
