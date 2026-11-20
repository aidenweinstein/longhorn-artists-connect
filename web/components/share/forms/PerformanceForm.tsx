"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { PERFORMANCE_CATEGORIES } from "@/lib/shareOptions";
import { image, mediaDuration, raw, videoFrame } from "@/lib/shareUpload";
import { containStyle, croppedAspect, cropStyle, encodeCrop, type VideoCrop } from "@/lib/videoCrop";
import VideoCropEditor from "../VideoCropEditor";
import { canBuildPlaylists, searchPlaylistPosts, type PlaylistCandidate } from "@/app/(app)/share/playlistActions";
import { useReleaseYears, CreditLine, CreditsRow, CropIcon, DropZone, FileRow, FilesRow, ListRow, Section, SelectRow, TextArea, TextInput, VideoIcon, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

// The app calls this a Reel (ReelSubmissionView).
export default function PerformanceForm() {
  const years = useReleaseYears();
  const [category, setCategory] = useDraftField("category", "");
  // One video, or several in playing order for a showcase. Each has a title once there is more than one.
  const [videos, setVideos] = useDraftField<Clip[]>("videos", []);
  const video = videos[0]?.file ?? null;
  // The post stores one playback crop (reelVideoCrop), for the first video, as in the app.
  const videoCrop = videos[0]?.crop ?? null;
  // Admins only: existing Nexus posts to play after the uploads. They leave the feeds and show only in this playlist.
  const [admin, setAdmin] = useState(false);
  const [existing, setExisting] = useDraftField<PlaylistCandidate[]>("existing", []);
  useEffect(() => {
    let live = true;
    canBuildPlaylists().then((ok) => live && setAdmin(ok)).catch(() => {});
    return () => {
      live = false;
    };
  }, []);
  const [thumbnail, setThumbnail] = useDraftField<File | null>("thumbnail", null);
  const [title, setTitle] = useDraftField("title", "");
  const [description, setDescription] = useDraftField("description", "");
  const [year, setYear] = useDraftField("year", "");
  const [featured, setFeatured] = useDraftField<string[]>("featured", []);
  // Theatre Show only: production photos and the cast (character + actor).
  const [photos, setPhotos] = useDraftField<File[]>("photos", []);
  const [cast, setCast] = useDraftField<Credit[]>("cast", [{ role: "", name: "" }]);

  const isTheatreShow = category === "Theatre Show";
  // A showcase: several videos, or videos from existing posts. It has a main thumbnail (its cover
  // in the feeds), a thumbnail for each video, and who performs in each video.
  const showcase = videos.length > 1 || existing.length > 0;

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [
    !video && !existing.length && !kept.has("videos") && "video",
    showcase && !thumbnail && !kept.has("thumbnail") && "main thumbnail",
    !title.trim() && "title",
  ].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="performance"
      title="Performance"
      missing={missing}
      draft={async () => {
        const poster = thumbnail ?? (video ? await videoFrame(video, videoCrop) : undefined);
        // Every uploaded video of a showcase gets a thumbnail: the one picked for it, else a
        // frame from the video, else the main one. All or none, so they stay lined up.
        const clipThumbs = showcase
          ? await Promise.all(videos.map(async (v, i) => v.thumb ?? (await videoFrame(v.file, i === 0 ? v.crop : null)) ?? poster))
          : [];
        const thumbsReady = clipThumbs.length > 0 && clipThumbs.every((f): f is File => !!f);
        return {
          type: "performance",
          text: { title, description, category, releaseYear: year, videoCrop: encodeCrop(videoCrop) },
          credits: {
            cast: isTheatreShow ? cast.filter((c) => c.name.trim()) : [],
            // Who's in each uploaded video, lined up with them ("" for nobody named).
            videoCast: showcase ? videos.map((v) => ({ role: "Actor", name: v.actor?.name.trim() ?? "", profileID: v.actor?.profileID })) : [],
          },
          lists: { featured, playlistPostIDs: existing.map((p) => p.id), videoTitles: videos.length > 1 ? videos.map((v, i) => v.title.trim() || `Video ${i + 1}`) : [] },
          numbers: { videoDuration: (video && (await mediaDuration(video))) || 0 },
          flags: {},
          files: {
            reelVideo: video ? [raw(video)] : [],
            reelVideos: videos.slice(1).map((v) => raw(v.file)),
            reelThumbnail: poster ? [image(poster, 1000)] : [],
            reelVideoThumbnails: thumbsReady ? (clipThumbs as File[]).map((f) => image(f, 1000)) : [],
            reelStills: isTheatreShow ? photos.map((f) => image(f)) : [],
          },
        };
      }}
    >
      <Section title="Category">
        <SelectRow label="Category" value={category} options={PERFORMANCE_CATEGORIES} placeholder="Select Category" onChange={setCategory} />
      </Section>

      <>
          <Section
            title="Upload"
            footer={
              showcase
                ? "Videos play in this order, like a playlist. The main thumbnail is the showcase's cover in the feeds. Each video can have its own thumbnail (otherwise a frame from it is used) and the person in it, who's highlighted in the Cast list while their video plays."
                : undefined
            }
          >
            <VideoList videos={videos} onChange={setVideos} showcase={showcase} />
            <FileRow noun={showcase ? "main thumbnail" : "thumbnail"} accept="image/*" file={thumbnail} onChange={setThumbnail} optional={!showcase} />
            {isTheatreShow && <FilesRow noun="photos" accept="image/*" files={photos} onChange={setPhotos} optional />}
          </Section>

          {admin && (
            <Section
              title="Existing posts (admins)"
              footer="Posts added here play after any videos uploaded above. They stop showing on their own in the feeds and appear only in this playlist; they stay on people's portfolios."
            >
              <ExistingPosts picked={existing} onChange={setExisting} />
            </Section>
          )}

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder={isTheatreShow ? "Show title" : "Title"} />
            <TextArea value={description} onChange={setDescription} placeholder="Description" />
            <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
            {isTheatreShow && (
              <CreditsRow
                label="Cast"
                credits={cast}
                onChange={setCast}
                rolePlaceholder="Character"
                namePlaceholder="Actor"
                addLabel="Add cast member"
              />
            )}
          </Section>

          <Section title="Other" footer="Projects you're in that this reel draws from.">
            <ListRow label="Featured Work" items={featured} onChange={setFeatured} placeholder="Project name" addLabel="Add project" />
          </Section>
      </>
    </SubmissionShell>
  );
}

/** One uploaded video: its title, playback crop (first video only), own thumbnail and performer. */
type Clip = { file: File; title: string; crop?: VideoCrop | null; thumb?: File | null; actor?: Credit };

/**
 * A small picture of the video, so each one can be told apart while naming it. Shows a
 * frame from just after the start (the very first is often black); click to play or
 * pause it, silently, in place.
 */
function ClipThumb({ file, crop, picture }: { file: File; crop?: VideoCrop | null; picture?: File | null }) {
  const url = useMemo(() => URL.createObjectURL(file), [file]);
  useEffect(() => () => URL.revokeObjectURL(url), [url]);
  const pictureURL = useMemo(() => (picture ? URL.createObjectURL(picture) : null), [picture]);
  useEffect(() => () => void (pictureURL && URL.revokeObjectURL(pictureURL)), [pictureURL]);
  const [natural, setNatural] = useState(16 / 9);
  if (pictureURL) {
    // The thumbnail picked for this video.
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={pictureURL} alt="" className="h-14 w-24 shrink-0 rounded-lg bg-black object-cover" />;
  }
  if (crop) {
    // Just the cropped area, fitted inside the thumbnail.
    return (
      <span className="relative h-14 w-24 shrink-0 overflow-hidden rounded-lg bg-black">
        <span className="overflow-hidden" style={containStyle(96 / 56, croppedAspect(natural, crop))}>
          <video
            src={`${url}#t=0.5`}
            muted
            playsInline
            preload="metadata"
            onLoadedMetadata={(e) => {
              const v = e.currentTarget;
              if (v.videoWidth && v.videoHeight) setNatural(v.videoWidth / v.videoHeight);
            }}
            style={cropStyle(crop)}
            className="object-fill"
          />
        </span>
      </span>
    );
  }
  return (
    <video
      src={`${url}#t=0.5`}
      muted
      playsInline
      preload="metadata"
      title="Click to play or pause"
      onClick={(e) => {
        const el = e.currentTarget;
        if (el.paused) void el.play().catch(() => {});
        else el.pause();
      }}
      className="h-14 w-24 shrink-0 cursor-pointer rounded-lg bg-black object-cover"
    />
  );
}

/**
 * The post's videos in playing order: one for a reel, several for a showcase. Reorderable;
 * in a showcase each has a title, its own thumbnail and the person performing in it.
 */
function VideoList({ videos, onChange, showcase }: { videos: Clip[]; onChange: (v: Clip[]) => void; showcase: boolean }) {
  const patch = (i: number, p: Partial<Clip>) => onChange(videos.map((x, j) => (j === i ? { ...x, ...p } : x)));
  const move = (i: number, by: number) => {
    const next = [...videos];
    const [v] = next.splice(i, 1);
    next.splice(i + by, 0, v);
    onChange(next);
  };
  const add = (files: File[]) => onChange([...videos, ...files.map((file) => ({ file, title: "" }))]);
  const [cropping, setCropping] = useState<number | null>(null);
  const editing = cropping === null ? undefined : videos[cropping];
  return (
    <>
      {editing && (
        <VideoCropEditor
          file={editing.file}
          initial={editing.crop ?? null}
          onCancel={() => setCropping(null)}
          onDone={(crop) => {
            onChange(videos.map((x) => (x === editing ? { ...x, crop } : x)));
            setCropping(null);
          }}
        />
      )}
      {videos.map((v, i) => (
        <div key={`${v.file.name}-${v.file.lastModified}-${i}`} className="px-4 py-2.5">
        <div className="flex min-h-12 flex-wrap items-center gap-x-3 gap-y-1">
          <ClipThumb file={v.file} crop={i === 0 ? v.crop : null} picture={showcase ? v.thumb : null} />
          <span className="w-16 shrink-0 text-[15px]">Video {i + 1}</span>
          <span className="min-w-0 flex-1 truncate text-sm text-muted">{v.file.name}</span>
          {showcase && <ClipThumbPicker picture={v.thumb ?? null} index={i} onChange={(thumb) => patch(i, { thumb })} />}
          {i === 0 && (
            <button
              type="button"
              aria-label={v.crop ? "Edit the crop of video 1" : "Crop video 1"}
              title={v.crop ? "Edit crop" : "Crop"}
              onClick={() => setCropping(i)}
              className={`px-1 hover:text-foreground ${v.crop ? "text-brand" : "text-muted"}`}
            >
              <CropIcon />
            </button>
          )}
          <button type="button" aria-label={`Move video ${i + 1} up`} disabled={i === 0} onClick={() => move(i, -1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↑</button>
          <button type="button" aria-label={`Move video ${i + 1} down`} disabled={i === videos.length - 1} onClick={() => move(i, 1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↓</button>
          <button type="button" aria-label={`Remove video ${i + 1}`} onClick={() => onChange(videos.filter((_, j) => j !== i))} className="px-1 text-lg leading-none text-muted hover:text-foreground">×</button>
        </div>
        {showcase && (
          // The video's title and who's in it: typing a name suggests Nexus members, and picking
          // one links their profile (and credits them in the Cast list).
          <div className="mt-2">
            <CreditLine
              credit={{ role: v.title, name: v.actor?.name ?? "", profileID: v.actor?.profileID }}
              index={i}
              rolePlaceholder="Title or scene"
              namePlaceholder="Actor"
              onChange={(c) =>
                patch(i, {
                  ...(c.role !== undefined && { title: c.role.slice(0, 200) }),
                  ...((c.name !== undefined || "profileID" in c) && {
                    actor: { role: "Actor", name: c.name ?? v.actor?.name ?? "", profileID: "profileID" in c ? c.profileID : v.actor?.profileID },
                  }),
                })
              }
            />
          </div>
        )}
        </div>
      ))}
      <div className="p-3">
        <DropZone
          accept="video/*"
          multiple
          compact={videos.length > 0}
          onFiles={add}
          icon={<VideoIcon />}
          title={videos.length ? "Add more videos" : "Select video"}
          hint={videos.length ? undefined : "Add several to make a playlist, like an actor showcase"}
        />
      </div>
    </>
  );
}

/** Picks (or clears) one showcase video's own thumbnail. */
function ClipThumbPicker({ picture, index, onChange }: { picture: File | null; index: number; onChange: (f: File | null) => void }) {
  const input = useRef<HTMLInputElement>(null);
  return (
    <span className="flex shrink-0 items-center gap-1">
      <input
        ref={input}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f && f.type.startsWith("image/")) onChange(f);
          e.target.value = "";
        }}
      />
      <button
        type="button"
        onClick={() => input.current?.click()}
        aria-label={picture ? `Change the thumbnail of video ${index + 1}` : `Add a thumbnail for video ${index + 1}`}
        className="rounded-full border border-border px-2.5 py-0.5 text-xs font-medium hover:bg-foreground/5"
      >
        {picture ? "Change thumbnail" : "Add thumbnail"}
      </button>
      {picture && (
        <button
          type="button"
          onClick={() => onChange(null)}
          aria-label={`Use a frame from video ${index + 1} as its thumbnail`}
          title="Use a frame from the video instead"
          className="px-1 text-muted hover:text-foreground"
        >
          ×
        </button>
      )}
    </span>
  );
}

/** Admins: search Nexus posts that have a video and line them up for the playlist. */
function ExistingPosts({ picked, onChange }: { picked: PlaylistCandidate[]; onChange: (p: PlaylistCandidate[]) => void }) {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<PlaylistCandidate[] | null>(null);
  const [searching, setSearching] = useState(false);

  async function search() {
    setSearching(true);
    try {
      setResults(await searchPlaylistPosts(q));
    } catch {
      setResults([]);
    } finally {
      setSearching(false);
    }
  }
  const move = (i: number, by: number) => {
    const next = [...picked];
    const [p] = next.splice(i, 1);
    next.splice(i + by, 0, p);
    onChange(next);
  };
  const has = (id: string) => picked.some((p) => p.id === id);
  const thumb = "h-14 w-24 shrink-0 rounded-lg bg-black object-cover";

  return (
    <>
      {picked.map((p, i) => (
        <div key={p.id} className="flex min-h-12 items-center gap-3 px-4 py-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {p.thumb ? <img src={p.thumb} alt="" className={thumb} /> : <span className={thumb} />}
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[15px]">{p.title}</span>
            <span className="block truncate text-sm text-muted">{p.creator}</span>
          </span>
          <button type="button" aria-label={`Move ${p.title} up`} disabled={i === 0} onClick={() => move(i, -1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↑</button>
          <button type="button" aria-label={`Move ${p.title} down`} disabled={i === picked.length - 1} onClick={() => move(i, 1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↓</button>
          <button type="button" aria-label={`Remove ${p.title}`} onClick={() => onChange(picked.filter((x) => x.id !== p.id))} className="px-1 text-lg leading-none text-muted hover:text-foreground">×</button>
        </div>
      ))}
      <div className="flex items-center gap-2 px-4 py-2.5">
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void search();
            }
          }}
          placeholder="Search posts by title or name"
          aria-label="Search existing posts"
          className="min-w-0 flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted"
        />
        <button type="button" onClick={() => void search()} disabled={searching} className="rounded-full border border-border px-3 py-1 text-sm font-medium hover:bg-foreground/5 disabled:opacity-60">
          {searching ? "Searching…" : "Search"}
        </button>
      </div>
      {results && results.length === 0 && <p className="px-4 py-2.5 text-sm text-muted">No posts with a video match that.</p>}
      {results?.map((p) => (
        <div key={p.id} className="flex min-h-12 items-center gap-3 px-4 py-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {p.thumb ? <img src={p.thumb} alt="" className={thumb} /> : <span className={thumb} />}
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[15px]">{p.title}</span>
            <span className="block truncate text-sm text-muted">{p.creator}</span>
          </span>
          <button
            type="button"
            disabled={has(p.id)}
            onClick={() => onChange([...picked, p])}
            className="rounded-full bg-brand px-3 py-1 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-40"
          >
            {has(p.id) ? "Added" : "Add"}
          </button>
        </div>
      ))}
    </>
  );
}

