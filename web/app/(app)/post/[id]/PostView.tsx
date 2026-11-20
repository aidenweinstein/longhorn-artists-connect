import { notFound } from "next/navigation";
import MaskImage from "@/components/MaskImage";
import MediaViewer from "@/components/MediaViewer";
import Avatar from "@/components/Avatar";
import { TINT, creditPrefix } from "@/components/ContentGrid";
import { avatarSource, gallerySources, thumbSrc } from "@/lib/smallImage";
import PersonLink, { MainArtistLinks } from "@/components/PersonLink";
import AvatarStack from "@/components/AvatarStack";
import ImageCarousel from "@/components/ImageCarousel";
import { getCategory } from "@/lib/categories";
import type { CSSProperties } from "react";
import { feedPosts, findPost } from "@/lib/content";
import type { Post } from "@/lib/mockContent";
import { schoolSlugForName, type School } from "@/lib/schools";
import { detailsFor, type Credit } from "@/lib/postDetails";
import PostMedia from "@/components/PostMedia";
import Player from "@/components/Player";
import MusicPlayer from "@/components/MusicPlayer";
import VideoPlaylist from "@/components/VideoPlaylist";
import { PlaylistProvider } from "@/components/PlaylistContext";
import ShowcaseCast, { type ShowcaseCastRow } from "@/components/ShowcaseCast";
import ServiceBadge from "@/components/ServiceBadge";
import PostLink from "@/components/PostLink";
import EditPostLink from "@/components/EditPostLink";
import PostActions from "@/components/PostActions";
import Timecode from "@/components/Timecode";

/** One row per person: someone credited twice in a group gets both roles on their row. */
function mergeRoles(credits: Credit[]): Credit[] {
  const rows = new Map<string, Credit>();
  for (const c of credits) {
    const key = c.name.trim().toLowerCase();
    const row = rows.get(key);
    if (!row) rows.set(key, { ...c });
    else if (c.role && !row.role.split(", ").includes(c.role)) row.role = row.role ? `${row.role}, ${c.role}` : c.role;
  }
  return [...rows.values()];
}

/**
 * A post's page. Opened from a school's feed (`school`, at /school/<slug>/post/<id>) it
 * stays in that school's colors, the sidebar keeps that school selected, and "More on
 * Nexus" leads with that school's posts, which open the same way.
 */
export default async function PostView({ id, school }: { id: string; school?: School }) {
  const post = await findPost(id);
  if (!post) notFound();
  const feed = await feedPosts();
  // Posts by or crediting someone at the school (an early app post with no school is UT Austin's).
  const atSchool = (p: Post) => !!school && (p.schoolSlugs ?? [schoolSlugForName(p.school)]).includes(school.slug);

  const cat = getCategory(post.category)!;
  const d = post.details ?? detailsFor(post);
  const meta = [
    d.kindLabel,
    ...d.genres,
    // The studio sits opposite the main credits instead (below).
    d.releaseYear,
  ].filter(Boolean) as string[];
  // Photo and design posts show their pictures in the main carousel; posts led by
  // a video or song get a second carousel for their stills further down.
  const playsMedia = Boolean(post.videoUrl || post.audioUrl);
  // Screen-sized copies load in the carousel; each picture's upload opens from "Full size".
  const originals = post.images ?? [];
  const gallery = gallerySources(post);
  const pictures = playsMedia ? [] : gallery.length ? gallery : post.thumbnailUrl ? [post.thumbnailUrl] : [];
  const related = feed.filter((p) => p.id !== post.id && p.category === post.category)
    .concat(feed.filter((p) => p.category !== post.category));
  // From a school's feed, that school's posts come first.
  const more = (school ? related.filter(atSchool).concat(related.filter((p) => !atSchool(p))) : related).slice(0, 6);

  // A showcase (several videos): its Cast lists who's in each video, highlights whoever is
  // playing and switches the player to anyone picked. Pictures come from the post's credits.
  const playlist = post.videos && post.videos.length > 1 ? post.videos : undefined;
  const castCredits = d.creditGroups.find((g) => g.title === "Cast")?.credits ?? [];
  const inVideos = (c: Credit) =>
    (playlist ?? []).some((v) => v.actor && ((v.actor.profileID && v.actor.profileID === c.profileID) || v.actor.name.toLowerCase() === c.name.toLowerCase()));
  const castRows: ShowcaseCastRow[] = (playlist ?? []).flatMap((v, i) => {
    if (!v.actor?.name) return [];
    const a = v.actor;
    const known = castCredits.find((c) => (a.profileID && c.profileID === a.profileID) || c.name.toLowerCase() === a.name.toLowerCase());
    const person = { ...a, ...(known && { profileID: known.profileID ?? a.profileID, avatarUrl: known.avatarUrl ?? a.avatarUrl, avatarKey: known.avatarKey ?? a.avatarKey }) };
    return [{
      index: i,
      role: v.title || `Video ${i + 1}`,
      person: (
        <PersonLink name={person.name} profileID={person.profileID} className="group/person flex items-center gap-2.5 hover:no-underline">
          {person.profileID && <Avatar name={person.name} src={avatarSource(person)} size="sm" />}
          <span className={`text-sm font-medium ${person.profileID ? "group-hover/person:underline" : ""}`}>{person.name}</span>
        </PersonLink>
      ),
    }];
  });
  // Cast credits not in any video (a Theatre Show's other cast) keep the usual list, under the showcase's.
  const otherGroups = castRows.length
    ? d.creditGroups
        .map((g) => (g.title === "Cast" ? { ...g, title: "More Cast", credits: g.credits.filter((c) => !inVideos(c)) } : g))
        .filter((g) => g.credits.length > 0)
    : d.creditGroups;

  return (
    <div
      // Like the school's feed: its secondary color (Berkeley, USC and Michigan gold) stands in for the brand color, e.g. the player's progress bar.
      style={school ? ({ "--brand": school.accent } as CSSProperties) : undefined}
      className="mx-auto flex max-w-[1920px] flex-col gap-6 xl:flex-row"
    >
      <PlaylistProvider key={post.id} count={playlist?.length ?? 0} autoStart>
      <div className="min-w-0 flex-1">
        {playlist ? (
          <VideoPlaylist key={post.id} postID={post.id} videos={playlist} poster={post.thumbnailUrl} aspect={post.aspect} crop={post.videoCrop} autoStart />
        ) : post.videoUrl ? (
          <Player key={post.id} postID={post.id} src={post.videoUrl} poster={post.thumbnailUrl} aspect={post.aspect} crop={post.videoCrop} autoStart />
        ) : post.tracks ? (
          <MusicPlayer key={post.id} tracks={post.tracks} poster={post.thumbnailUrl} aspect={post.aspect} firstDuration={post.duration} autoStart />
        ) : post.audioUrl ? (
          <Player key={post.id} postID={post.id} src={post.audioUrl} poster={post.thumbnailUrl} aspect={post.aspect} audioOnly autoStart />
        ) : pictures.length > 0 ? (
          <ImageCarousel key={post.id} images={pictures} originals={originals} aspect={post.aspect} />
        ) : (
          <MediaViewer aspect={post.aspect}>
            <PostMedia post={post} />
          </MediaViewer>
        )}

        <div className="mt-5 flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
          <h1 className="min-w-0 text-2xl font-bold leading-tight">{post.title}</h1>
          <div className="flex items-center gap-2">
            <EditPostLink postID={post.id} type={post.category} makerProfileID={post.makerProfileID ?? post.creatorProfileID} editorIDs={post.editorIDs} />
            <PostActions postID={post.id} title={post.title} />
          </div>
        </div>
        {d.byline && (
          <p className="mt-1 text-lg text-muted">
            <PersonLink name={d.byline} profileID={post.creatorProfileID} className="hover:text-foreground" />
          </p>
        )}

        {meta.length > 0 && (
          <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted">
            {d.ageRating && (
              <span className="rounded border border-muted/60 px-1.5 py-0.5 text-xs font-semibold">{d.ageRating}</span>
            )}
            <span>{meta.join(" • ")}</span>
            {d.explicit && (
              <span className="rounded bg-foreground/15 px-1.5 py-0.5 text-xs font-semibold text-foreground">Explicit</span>
            )}
          </div>
        )}

        <div className="mt-4 flex items-center justify-between gap-4">
          <div className="flex min-w-0 items-center gap-3">
            <AvatarStack post={post} size="md" />
            <div className="min-w-0">
              <p>
                <span className="text-muted">{creditPrefix(post)}</span> <span className="font-semibold"><MainArtistLinks post={post} /></span>
              </p>
              {post.school && <p className="text-sm text-muted">{post.school}</p>}
            </div>
          </div>
          {d.studio && (
            // The studio or organization behind the work, opposite the main credits.
            <div className="min-w-0 shrink text-right">
              <p className="text-xs uppercase tracking-wide text-muted">Org/Class</p>
              <p className="truncate font-semibold">{d.studio}</p>
            </div>
          )}
        </div>

        <section className="mt-5 space-y-6 rounded-2xl bg-surface p-5">
          {(d.logline || d.description) && (
            <div>
              {d.logline && <p className="font-medium">{d.logline}</p>}
              {d.description && <p className={`${d.logline ? "mt-2 " : ""}leading-relaxed text-foreground/85`}>{d.description}</p>}
            </div>
          )}

          {castRows.length > 0 && <ShowcaseCast rows={castRows} />}

          {otherGroups.map((group) => (
            <div key={group.title}>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">{group.title}</h2>
              <ul className="mt-3 divide-y divide-border">
                {mergeRoles(group.credits).map((c) => (
                  <li key={`${c.role}-${c.name}`} className="flex items-center justify-between gap-4 py-2.5">
                    <span className="text-sm text-muted">{c.role}</span>
                    <PersonLink name={c.name} profileID={c.profileID} className="group/person flex items-center gap-2.5 hover:no-underline">
                      {c.profileID && <Avatar name={c.name} src={avatarSource(c)} size="sm" />}
                      <span className={`text-sm font-medium ${c.profileID ? "group-hover/person:underline" : ""}`}>{c.name}</span>
                    </PersonLink>
                  </li>
                ))}
              </ul>
            </div>
          ))}

          {d.equipment && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Equipment</h2>
              <ul className="mt-3 divide-y divide-border">
                {d.equipment.map((e) => (
                  <li key={e.label} className="flex items-center justify-between gap-4 py-2.5 text-sm">
                    <span className="text-muted">{e.label}</span>
                    <span className="font-medium">{e.value}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {d.featuredWork && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Featured Work</h2>
              <ul className="mt-3 space-y-1.5 text-sm font-medium">
                {d.featuredWork.map((w) => <li key={w}>{w}</li>)}
              </ul>
            </div>
          )}

          {d.trailerUrl && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Trailer</h2>
              <div className="mt-3 max-w-md">
                <Player src={d.trailerUrl} aspect={16 / 9} />
              </div>
            </div>
          )}

          {d.hasTrailer && !d.trailerUrl && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Trailer</h2>
              <div className={`mt-3 flex aspect-video max-w-md items-center justify-center rounded-xl bg-gradient-to-br ${TINT[post.category]}`}>
                <MaskImage src={cat.icon} ratio={cat.ratio} className="h-10 text-white/35" />
              </div>
            </div>
          )}

          {d.alsoOn && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Also On</h2>
              <div className="mt-3 flex flex-wrap gap-2">
                {d.alsoOn.map((s) => (
                  <ServiceBadge key={s} service={s} />
                ))}
              </div>
            </div>
          )}

          {d.links && d.links.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Also On</h2>
              <div className="mt-3 flex flex-wrap gap-2">
                {d.links.map(([name, url]) => (
                  <ServiceBadge key={name} service={name} url={url} />
                ))}
              </div>
            </div>
          )}

          {post.videoUrl && post.tracks && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Tracks</h2>
              <div className="mt-3 max-w-md">
                <MusicPlayer tracks={post.tracks} poster={post.thumbnailUrl} aspect={post.aspect} firstDuration={post.duration} />
              </div>
            </div>
          )}

          {playsMedia && gallery.length > 0 && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Gallery</h2>
              <div className="mt-3">
                <ImageCarousel images={gallery} originals={originals} aspect={16 / 9} />
              </div>
            </div>
          )}

          {d.lyrics && (
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Lyrics</h2>
              <p className="mt-3 whitespace-pre-line text-sm text-foreground/85">{d.lyrics}</p>
            </div>
          )}

        </section>
      </div>
      </PlaylistProvider>

      <aside className="w-full shrink-0 xl:w-[340px]">
        <h2 className="mb-4 font-semibold">More on Nexus</h2>
        <ul className="flex flex-col gap-3">
          {more.map((p) => {
            const c = getCategory(p.category)!;
            return (
              <li key={p.id}>
                <div className="flex gap-3 rounded-xl p-1 hover:bg-surface">
                  {/* Thumbnail keeps its own shape (at most 160 wide, 90 tall), so no bars. */}
                  <PostLink postID={p.id} school={atSchool(p) ? school?.slug : undefined} mediaUrl={p.videoUrl ?? p.audioUrl} className="flex w-40 shrink-0 items-start justify-center">
                    <div
                      style={{ aspectRatio: p.aspect, width: Math.min(160, 90 * p.aspect) }}
                      className={`relative flex items-center justify-center overflow-hidden rounded-lg bg-gradient-to-br ${TINT[p.category]}`}
                    >
                      <MaskImage src={c.icon} ratio={c.ratio} className="h-7 text-white/35" />
                      {p.thumbnailUrl && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={thumbSrc(p)} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover" />
                      )}
                      {(p.duration || p.videoUrl || p.audioUrl) && (
                        <Timecode seconds={p.duration} src={p.videoUrl ?? p.audioUrl} kind={p.videoUrl ? "video" : "audio"} small />
                      )}
                    </div>
                  </PostLink>
                  <div className="min-w-0 py-0.5">
                    <PostLink postID={p.id} school={atSchool(p) ? school?.slug : undefined} mediaUrl={p.videoUrl ?? p.audioUrl} className="line-clamp-2 text-sm font-semibold leading-snug">{p.title}</PostLink>
                    <p className="mt-1 text-xs text-muted"><MainArtistLinks post={p} className="hover:text-foreground" /></p>
                    <p className="text-xs text-muted">{[c.label, (p.details ?? detailsFor(p)).releaseYear].filter(Boolean).join(" · ")}</p>
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      </aside>
    </div>
  );
}
