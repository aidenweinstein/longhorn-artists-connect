"use client";

import { useState } from "react";
import { MUSIC_CATEGORIES, MUSIC_GENRES, PRODUCTION_ROLES, RECORDING_ROLES, STREAMING_SERVICES, releaseYears } from "@/lib/shareOptions";
import { AudioIcon, DisclosureRow, FileRow, FilesRow, MultiSelectRow, Section, SelectRow, SubField, TextInput, ToggleRow, VideoIcon, filledCredits, seedCredits, subInput } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

export default function MusicForm() {
  const [category, setCategory] = useState("");
  const [tracks, setTracks] = useState<File[]>([]);
  const [cover, setCover] = useState<File | null>(null);
  const [musicVideo, setMusicVideo] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [artist, setArtist] = useState("");
  const [genres, setGenres] = useState<string[]>([]);
  const [year, setYear] = useState("");
  const [recording, setRecording] = useState(() => seedCredits(RECORDING_ROLES));
  const [production, setProduction] = useState(() => seedCredits(PRODUCTION_ROLES));
  const [explicit, setExplicit] = useState(false);
  const [links, setLinks] = useState<Record<string, string>>({});
  const [lyrics, setLyrics] = useState("");

  const multiTrack = category === "EP" || category === "Album";
  const showsStreamingLinks = category !== "Performance";
  const showsLyrics = category === "Song";
  const hasCredits = filledCredits(recording).length + filledCredits(production).length > 0;

  const missing = [
    !category && "category",
    !tracks.length && (multiTrack ? "tracks" : "audio file"),
    !title.trim() && "title",
    !artist.trim() && "artist",
  ].filter(Boolean) as string[];

  return (
    <SubmissionShell title="Music" missing={missing}>
      <Section title="Category">
        <SelectRow
          label="Category"
          value={category}
          options={MUSIC_CATEGORIES}
          placeholder="Select Category"
          onChange={(v) => {
            setCategory(v);
            // A single keeps only its first track.
            if (v !== "EP" && v !== "Album") setTracks((t) => t.slice(0, 1));
          }}
        />
      </Section>

      {category && (
        <>
          <Section title="Upload" footer={multiTrack ? "Tracks play in this order. The first is the lead track." : undefined}>
            {multiTrack ? (
              <TrackList tracks={tracks} onChange={setTracks} />
            ) : (
              <FileRow noun="audio file" accept="audio/*" file={tracks[0] ?? null} onChange={(f) => setTracks(f ? [f] : [])} icon={<AudioIcon />} />
            )}
            <FileRow noun={multiTrack ? "album cover" : "cover art"} accept="image/*" file={cover} onChange={setCover} optional />
            <FileRow noun="music video" accept="video/*" file={musicVideo} onChange={setMusicVideo} icon={<VideoIcon />} optional />
          </Section>

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder="Title" />
            <TextInput value={artist} onChange={setArtist} placeholder="Artist" />
            <MultiSelectRow label="Genres" values={genres} options={MUSIC_GENRES} onChange={setGenres} />
            <SelectRow label="Release Year" value={year} options={releaseYears()} onChange={setYear} />
            <DisclosureRow label="Credits" edited={hasCredits}>
              <p className="pt-1 text-xs font-semibold uppercase tracking-wide text-muted">Recording</p>
              <InlineCredits credits={recording} onChange={setRecording} placeholder="Role (e.g., Lead Vocals, Guitar)" />
              <p className="pt-2 text-xs font-semibold uppercase tracking-wide text-muted">Production</p>
              <InlineCredits credits={production} onChange={setProduction} placeholder="Role (e.g., Producer, Mix Engineer)" />
            </DisclosureRow>
            <ToggleRow label="Explicit" checked={explicit} onChange={setExplicit} />
          </Section>

          {(showsStreamingLinks || showsLyrics) && (
            <Section title="Other">
              {showsStreamingLinks && (
                <DisclosureRow label="Streaming Links" edited={Object.values(links).some((l) => l.trim())}>
                  {STREAMING_SERVICES.map((s) => (
                    <SubField key={s} label={s}>
                      <input
                        type="url"
                        className={subInput}
                        placeholder={`${s} link`}
                        value={links[s] ?? ""}
                        onChange={(e) => setLinks((l) => ({ ...l, [s]: e.target.value }))}
                      />
                    </SubField>
                  ))}
                </DisclosureRow>
              )}
              {showsLyrics && (
                <DisclosureRow label="Lyrics" edited={!!lyrics.trim()}>
                  <textarea
                    aria-label="Lyrics"
                    className={`${subInput} min-h-48`}
                    placeholder="Enter lyrics"
                    value={lyrics}
                    maxLength={10000}
                    onChange={(e) => setLyrics(e.target.value)}
                  />
                </DisclosureRow>
              )}
            </Section>
          )}
        </>
      )}
    </SubmissionShell>
  );
}

/** EP/Album tracklist: numbered tracks, reorderable, added from files. */
function TrackList({ tracks, onChange }: { tracks: File[]; onChange: (t: File[]) => void }) {
  const move = (i: number, by: number) => {
    const next = [...tracks];
    const [t] = next.splice(i, 1);
    next.splice(i + by, 0, t);
    onChange(next);
  };
  return (
    <>
      {tracks.map((t, i) => (
        <div key={`${t.name}-${i}`} className="flex min-h-12 items-center gap-3 px-4 py-2.5">
          <span className="w-16 shrink-0 text-[15px]">Track {i + 1}</span>
          <span className="min-w-0 flex-1 truncate text-sm text-muted">{t.name}</span>
          <button type="button" aria-label={`Move track ${i + 1} up`} disabled={i === 0} onClick={() => move(i, -1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↑</button>
          <button type="button" aria-label={`Move track ${i + 1} down`} disabled={i === tracks.length - 1} onClick={() => move(i, 1)} className="px-1 text-muted hover:text-foreground disabled:invisible">↓</button>
          <button type="button" aria-label={`Remove track ${i + 1}`} onClick={() => onChange(tracks.filter((_, j) => j !== i))} className="px-1 text-lg leading-none text-muted hover:text-foreground">×</button>
        </div>
      ))}
      <FilesRow noun="tracks" accept="audio/*" files={[]} onChange={(added) => onChange([...tracks, ...added])} icon={<AudioIcon />} />
    </>
  );
}

function InlineCredits({ credits, onChange, placeholder }: { credits: { role: string; name: string }[]; onChange: (c: { role: string; name: string }[]) => void; placeholder: string }) {
  const update = (i: number, patch: Partial<{ role: string; name: string }>) => onChange(credits.map((c, j) => (j === i ? { ...c, ...patch } : c)));
  return (
    <div className="space-y-2">
      {credits.map((c, i) => (
        <div key={i} className="flex items-center gap-2">
          <input aria-label={`Role ${i + 1}`} className={`${subInput} w-2/5`} placeholder={placeholder} value={c.role} onChange={(e) => update(i, { role: e.target.value })} />
          <input aria-label={`Name for ${c.role || `role ${i + 1}`}`} className={`${subInput} min-w-0 flex-1`} placeholder="Name" value={c.name} onChange={(e) => update(i, { name: e.target.value })} />
          <button type="button" aria-label={`Remove ${c.role || "row"}`} onClick={() => onChange(credits.filter((_, j) => j !== i))} className="h-7 w-7 shrink-0 text-lg leading-none text-muted hover:text-foreground">×</button>
        </div>
      ))}
      <button type="button" onClick={() => onChange([...credits, { role: "", name: "" }])} className="text-sm font-medium text-brand">
        + Add credit
      </button>
    </div>
  );
}

