"use client";

import { MUSIC_CATEGORIES, MUSIC_GENRES, PRODUCTION_ROLES, RECORDING_ROLES, STREAMING_SERVICES } from "@/lib/shareOptions";
import { extension, image, mediaDuration, raw } from "@/lib/shareUpload";
import { useReleaseYears, AudioIcon, CreditLine, DisclosureRow, FileRow, FilesRow, MultiSelectRow, Section, SelectRow, SubField, TextInput, ToggleRow, VideoIcon, filledCredits, seedCredits, subInput, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

export default function MusicForm() {
  const years = useReleaseYears();
  const [category, setCategory] = useDraftField("category", "");
  const [tracks, setTracks] = useDraftField<File[]>("tracks", []);
  const [cover, setCover] = useDraftField<File | null>("cover", null);
  const [musicVideo, setMusicVideo] = useDraftField<File | null>("musicVideo", null);
  const [title, setTitle] = useDraftField("title", "");
  const [artist, setArtist] = useDraftField("artist", "");
  const [genres, setGenres] = useDraftField<string[]>("genres", []);
  const [year, setYear] = useDraftField("year", "");
  const [recording, setRecording] = useDraftField("recording", () => seedCredits(RECORDING_ROLES));
  const [production, setProduction] = useDraftField("production", () => seedCredits(PRODUCTION_ROLES));
  const [explicit, setExplicit] = useDraftField("explicit", false);
  const [links, setLinks] = useDraftField<Record<string, string>>("links", {});
  const [lyrics, setLyrics] = useDraftField("lyrics", "");

  const multiTrack = category === "EP" || category === "Album";
  const showsStreamingLinks = category !== "Performance";
  // No category yet behaves like a single Song.
  const showsLyrics = category === "Song" || category === "";
  const hasCredits = filledCredits(recording).length + filledCredits(production).length > 0;

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [
    !tracks.length && !kept.has("tracks") && (multiTrack ? "tracks" : "audio file"),
    !title.trim() && "title",
    !artist.trim() && "artist",
  ].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="music"
      title="Music"
      missing={missing}
      draft={async () => {
        const [lead, ...rest] = tracks;
        return {
          type: "music",
          text: {
            title,
            artist,
            category,
            releaseYear: year,
            lyrics: showsLyrics ? lyrics : "",
            audioExt: lead ? extension(lead, "m4a") : "m4a",
            spotify: showsStreamingLinks ? links["Spotify"] ?? "" : "",
            appleMusic: showsStreamingLinks ? links["Apple Music"] ?? "" : "",
            youtubeMusic: showsStreamingLinks ? links["YouTube Music"] ?? "" : "",
            soundcloud: showsStreamingLinks ? links["SoundCloud"] ?? "" : "",
          },
          lists: { genres, trackExts: rest.map((t) => extension(t, "m4a")) },
          credits: { recording: filledCredits(recording), production: filledCredits(production) },
          numbers: { audioDuration: (lead && (await mediaDuration(lead))) || 0 },
          flags: { explicit },
          files: {
            musicAudio: lead ? [raw(lead)] : [],
            musicTracks: multiTrack ? rest.map(raw) : [],
            musicCover: cover ? [image(cover, 1000)] : [],
            musicVideo: musicVideo ? [raw(musicVideo)] : [],
          },
        };
      }}
    >
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
            <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
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

function InlineCredits({ credits, onChange, placeholder }: { credits: Credit[]; onChange: (c: Credit[]) => void; placeholder: string }) {
  const update = (i: number, patch: Partial<Credit>) => onChange(credits.map((c, j) => (j === i ? { ...c, ...patch } : c)));
  return (
    <div className="space-y-2">
      {credits.map((c, i) => (
        <CreditLine key={i} credit={c} index={i} rolePlaceholder={placeholder} onChange={(patch) => update(i, patch)} onRemove={() => onChange(credits.filter((_, j) => j !== i))} />
      ))}
      <button type="button" onClick={() => onChange([...credits, { role: "", name: "" }])} className="text-sm font-medium text-brand">
        + Add credit
      </button>
    </div>
  );
}

