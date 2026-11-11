"use client";

import { useState } from "react";
import { AGE_RATINGS, CREW_ROLES, FILM_CATEGORIES, FILM_GENRES, FILM_STUDIOS, PRODUCTION_CLASSES, type FilmCategory } from "@/lib/shareOptions";
import { image, mediaDuration, raw, videoFrame } from "@/lib/shareUpload";
import { useReleaseYears, CreditsRow, FileRow, FilesRow, ListRow, MoreRows, MultiSelectRow, Section, Segmented, SelectRow, TextArea, TextInput, ToggleRow, VideoIcon, filledCredits, seedCredits } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

export default function FilmForm() {
  const years = useReleaseYears();
  const [category, setCategory] = useState<FilmCategory | "">("");
  const [studio, setStudio] = useState("");
  const [video, setVideo] = useState<File | null>(null);
  const [thumbnail, setThumbnail] = useState<File | null>(null);
  const [trailer, setTrailer] = useState<File | null>(null);
  const [bts, setBts] = useState<File[]>([]);
  const [stills, setStills] = useState<File[]>([]);
  const [title, setTitle] = useState("");
  const [logline, setLogline] = useState("");
  const [genres, setGenres] = useState<string[]>([]);
  const [year, setYear] = useState("");
  const [cast, setCast] = useState<string[]>([""]);
  const [crew, setCrew] = useState(() => seedCredits(CREW_ROLES));
  const [rating, setRating] = useState<string>("PG");
  const [festivalBound, setFestivalBound] = useState(false);

  const studioField = category === "Org Project" ? "Studio" : category === "Class Project" ? "Class" : null;

  const missing = [
    !video && "video",
    !title.trim() && "title",
    studioField && !studio && studioField.toLowerCase(),
  ].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="film"
      title="Film"
      missing={missing}
      draft={async () => {
        // No thumbnail picked: the video's first frame, as the app does.
        const poster = thumbnail ?? (video ? await videoFrame(video) : undefined);
        return {
          type: "film",
          text: { title, logline, studio, releaseYear: year, ageRating: rating },
          lists: { genres, cast },
          credits: { crew: filledCredits(crew) },
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
      <Section title="Category">
        <SelectRow
          label="Category"
          value={category}
          options={FILM_CATEGORIES}
          placeholder="Select Category"
          onChange={(v) => {
            setCategory(v as FilmCategory);
            setStudio(v === "Independent Project" ? "Independent" : "");
          }}
        />
      </Section>

      <Section title="Upload" footer="Films upload at full original quality.">
        <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} />
        <FileRow noun="thumbnail" accept="image/*" file={thumbnail} onChange={setThumbnail} optional />
        <MoreRows>
          <FileRow noun="trailer" accept="video/*" file={trailer} onChange={setTrailer} icon={<VideoIcon />} optional />
          <FilesRow noun="BTS photos" accept="image/*" files={bts} onChange={setBts} optional />
          <FilesRow noun="stills" accept="image/*" files={stills} onChange={setStills} optional />
        </MoreRows>
      </Section>

      <Section title="Details">
        <TextInput value={title} onChange={setTitle} placeholder="Title" />
        {studioField && (
          <SelectRow
            label={studioField}
            value={studio}
            options={studioField === "Studio" ? FILM_STUDIOS : PRODUCTION_CLASSES}
            onChange={setStudio}
          />
        )}
        <TextArea value={logline} onChange={setLogline} placeholder="Logline" maxLength={500} />
        <MultiSelectRow label="Genres" values={genres} options={FILM_GENRES} onChange={setGenres} />
        <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
        <ListRow label="Cast" items={cast} onChange={setCast} placeholder="Actor name" addLabel="Add cast member" />
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
