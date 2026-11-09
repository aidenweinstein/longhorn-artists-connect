"use client";

import { useState } from "react";
import { DESIGN_CATEGORIES, releaseYears } from "@/lib/shareOptions";
import { CreditsRow, FileRow, FilesRow, Section, SelectRow, TextArea, TextInput, VideoIcon, type Credit } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

export default function DesignForm() {
  const [category, setCategory] = useState("");
  const [images, setImages] = useState<File[]>([]);
  const [video, setVideo] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [year, setYear] = useState("");
  const [credits, setCredits] = useState<Credit[]>([{ role: "Designer", name: "" }]);

  const missing = [!category && "category", !images.length && "images", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell title="Design" missing={missing}>
      <Section title="Category">
        <SelectRow label="Category" value={category} options={DESIGN_CATEGORIES} placeholder="Select Category" onChange={setCategory} />
      </Section>

      {category && (
        <>
          <Section title="Upload" footer="The first image is the thumbnail. Add a video for motion or 3D work.">
            <FilesRow noun="images" accept="image/*" files={images} onChange={setImages} />
            <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} optional />
          </Section>

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder="Title" />
            <TextArea value={description} onChange={setDescription} placeholder="Description" />
            <SelectRow label="Release Year" value={year} options={releaseYears()} onChange={setYear} />
            <CreditsRow label="Credits" credits={credits} onChange={setCredits} addLabel="Add credit" />
          </Section>
        </>
      )}
    </SubmissionShell>
  );
}
