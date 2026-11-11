"use client";

import { useState } from "react";
import { PERFORMANCE_CATEGORIES } from "@/lib/shareOptions";
import { image, mediaDuration, raw, videoFrame } from "@/lib/shareUpload";
import { useReleaseYears, CreditsRow, FileRow, FilesRow, ListRow, Section, SelectRow, TextArea, TextInput, VideoIcon, type Credit } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

// The app calls this a Reel (ReelSubmissionView).
export default function PerformanceForm() {
  const years = useReleaseYears();
  const [category, setCategory] = useState("");
  const [video, setVideo] = useState<File | null>(null);
  const [thumbnail, setThumbnail] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [year, setYear] = useState("");
  const [featured, setFeatured] = useState<string[]>([]);
  // Theatre Show only: production photos and the cast (character + actor).
  const [photos, setPhotos] = useState<File[]>([]);
  const [cast, setCast] = useState<Credit[]>([{ role: "", name: "" }]);

  const isTheatreShow = category === "Theatre Show";

  const missing = [!video && "video", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="performance"
      title="Performance"
      missing={missing}
      draft={async () => {
        const poster = thumbnail ?? (video ? await videoFrame(video) : undefined);
        return {
          type: "performance",
          text: { title, description, category, releaseYear: year },
          lists: { featured },
          credits: { cast: isTheatreShow ? cast.filter((c) => c.name.trim()) : [] },
          numbers: { videoDuration: (video && (await mediaDuration(video))) || 0 },
          flags: {},
          files: {
            reelVideo: video ? [raw(video)] : [],
            reelThumbnail: poster ? [image(poster, 1000)] : [],
            reelStills: isTheatreShow ? photos.map((f) => image(f)) : [],
          },
        };
      }}
    >
      <Section title="Category">
        <SelectRow label="Category" value={category} options={PERFORMANCE_CATEGORIES} placeholder="Select Category" onChange={setCategory} />
      </Section>

      <>
          <Section title="Upload">
            <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} />
            <FileRow noun="thumbnail" accept="image/*" file={thumbnail} onChange={setThumbnail} optional />
            {isTheatreShow && <FilesRow noun="photos" accept="image/*" files={photos} onChange={setPhotos} optional />}
          </Section>

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
