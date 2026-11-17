"use client";

import { AGE_RATINGS, CREW_ROLES, FILM_CLASSES, FILM_GENRES, FILM_ORGS } from "@/lib/shareOptions";
import { image, mediaDuration, raw, videoFrame } from "@/lib/shareUpload";
import { encodeCrop, type VideoCrop } from "@/lib/videoCrop";
import { useReleaseYears, AffiliationRow, CreditsRow, FileRow, FilesRow, MoreRows, MultiSelectRow, Section, Segmented, SelectRow, TextArea, TextInput, ToggleRow, VideoIcon, filledCredits, seedCredits, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

export default function FilmForm() {
  const years = useReleaseYears();
  const [studio, setStudio] = useDraftField("studio", "");
  const [video, setVideo] = useDraftField<File | null>("video", null);
  const [videoCrop, setVideoCrop] = useDraftField<VideoCrop | null>("videoCrop", null);
  const [thumbnail, setThumbnail] = useDraftField<File | null>("thumbnail", null);
  const [trailer, setTrailer] = useDraftField<File | null>("trailer", null);
  const [bts, setBts] = useDraftField<File[]>("bts", []);
  const [stills, setStills] = useDraftField<File[]>("stills", []);
  const [title, setTitle] = useDraftField("title", "");
  const [logline, setLogline] = useDraftField("logline", "");
  const [genres, setGenres] = useDraftField<string[]>("genres", []);
  const [year, setYear] = useDraftField("year", "");
  const [cast, setCast] = useDraftField<Credit[]>("cast", [{ role: "", name: "" }]);
  const [crew, setCrew] = useDraftField("crew", () => seedCredits(CREW_ROLES));
  const [rating, setRating] = useDraftField<string>("rating", "PG");
  const [festivalBound, setFestivalBound] = useDraftField("festivalBound", false);

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [
    !video && !kept.has("video") && "video",
    !title.trim() && "title",
  ].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="film"
      title="Film"
      missing={missing}
      draft={async () => {
        // No thumbnail picked: the video's first frame, as the app does.
        const poster = thumbnail ?? (video ? await videoFrame(video, videoCrop) : undefined);
        return {
          type: "film",
          text: { title, logline, studio, releaseYear: year, ageRating: rating, videoCrop: encodeCrop(videoCrop) },
          lists: { genres },
          credits: { cast: filledCredits(cast), crew: filledCredits(crew) },
          numbers: { videoDuration: (video && (await mediaDuration(video))) || 0 },
          flags: { festivalBound },
          files: {
            filmVideo: video ? [raw(video)] : [],
            filmThumbnail: poster ? [image(poster, 1000)] : [],
            filmTrailer: trailer ? [raw(trailer)] : [],
            filmBTS: bts.map((f) => image(f)),
            filmStills: stills.map((f) => image(f)),
          },
        };
      }}
    >
      <Section title="Upload" footer="Films upload at full original quality.">
        <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} crop={videoCrop} onCropChange={setVideoCrop} />
        <FileRow noun="thumbnail" accept="image/*" file={thumbnail} onChange={setThumbnail} optional />
        <MoreRows>
          <FileRow noun="trailer" accept="video/*" file={trailer} onChange={setTrailer} icon={<VideoIcon />} optional />
          <FilesRow noun="BTS photos" accept="image/*" files={bts} onChange={setBts} optional />
          <FilesRow noun="stills" accept="image/*" files={stills} onChange={setStills} optional />
        </MoreRows>
      </Section>

      <Section title="Details">
        <TextInput value={title} onChange={setTitle} placeholder="Title" />
        <TextArea value={logline} onChange={setLogline} placeholder="Logline" maxLength={500} />
        <AffiliationRow
          label="Org/Class"
          value={studio}
          groups={[
            { title: "Orgs", options: FILM_ORGS },
            { title: "Classes", options: FILM_CLASSES },
          ]}
          onChange={setStudio}
        />
        <MultiSelectRow label="Genres" values={genres} options={FILM_GENRES} onChange={setGenres} />
        <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
        <CreditsRow label="Cast" credits={cast} onChange={setCast} rolePlaceholder="Role" namePlaceholder="Actor" addLabel="Add cast member" />
        <CreditsRow label="Crew" credits={crew} onChange={setCrew} />
        <Segmented label="Age Rating" value={rating} options={AGE_RATINGS} onChange={setRating} />
      </Section>

      <Section
        title="Other"
        footer="Keeps the actual film private while still showing thumbnail, logline, credits, etc. You can edit the post at any time to make it public when it's ready."
      >
        <ToggleRow label="Festival-Bound" checked={festivalBound} onChange={setFestivalBound} />
      </Section>
    </SubmissionShell>
  );
}
