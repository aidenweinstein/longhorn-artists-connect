"use client";

import { DESIGN_CATEGORIES } from "@/lib/shareOptions";
import { image, mediaDuration, raw, videoFrame } from "@/lib/shareUpload";
import { encodeCrop, type VideoCrop } from "@/lib/videoCrop";
import { useReleaseYears, CreditsRow, FileRow, FilesRow, Section, SelectRow, TextArea, TextInput, VideoIcon, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

export default function DesignForm() {
  const years = useReleaseYears();
  const [category, setCategory] = useDraftField("category", "");
  const [images, setImages] = useDraftField<File[]>("images", []);
  const [video, setVideo] = useDraftField<File | null>("video", null);
  const [videoCrop, setVideoCrop] = useDraftField<VideoCrop | null>("videoCrop", null);
  const [title, setTitle] = useDraftField("title", "");
  const [description, setDescription] = useDraftField("description", "");
  const [year, setYear] = useDraftField("year", "");
  const [credits, setCredits] = useDraftField<Credit[]>("credits", [{ role: "Designer", name: "" }]);

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [!images.length && !video && !kept.has("images") && !kept.has("video") && "images or a video", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="design"
      title="Design"
      missing={missing}
      draft={async () => {
        // The first image is the thumbnail; a video-only post uses the video's first frame.
        const poster = images[0] ?? (video ? await videoFrame(video, videoCrop) : undefined);
        return {
          type: "design",
          text: { title, description, category, releaseYear: year, videoCrop: encodeCrop(videoCrop) },
          lists: {},
          credits: { credits: credits.filter((c) => c.name.trim()) },
          numbers: { videoDuration: (video && (await mediaDuration(video))) || 0 },
          flags: {},
          files: {
            designImages: images.map((f) => image(f)),
            designVideo: video ? [raw(video)] : [],
            designThumbnail: poster ? [image(poster, 1000)] : [],
          },
        };
      }}
    >
      <Section title="Category">
        <SelectRow label="Category" value={category} options={DESIGN_CATEGORIES} placeholder="Select Category" onChange={setCategory} />
      </Section>

      <>
          <Section title="Upload" footer="The first image is the thumbnail. Add a video for motion or 3D work.">
            <FilesRow noun="images" accept="image/*" files={images} onChange={setImages} />
            <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} optional crop={videoCrop} onCropChange={setVideoCrop} />
          </Section>

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder="Title" />
            <TextArea value={description} onChange={setDescription} placeholder="Description" />
            <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
            <CreditsRow label="Credits" credits={credits} onChange={setCredits} addLabel="Add credit" />
          </Section>
      </>
    </SubmissionShell>
  );
}
