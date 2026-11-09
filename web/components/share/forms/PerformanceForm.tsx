"use client";

import { useState } from "react";
import { PERFORMANCE_CATEGORIES, releaseYears } from "@/lib/shareOptions";
import { FileIcon, FileRow, FilesRow, ListRow, MoreRows, Section, SelectRow, TextArea, TextInput, VideoIcon } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

// The app calls this a Reel (ReelSubmissionView).
export default function PerformanceForm() {
  const [category, setCategory] = useState("");
  const [video, setVideo] = useState<File | null>(null);
  const [thumbnail, setThumbnail] = useState<File | null>(null);
  const [headshots, setHeadshots] = useState<File[]>([]);
  const [resume, setResume] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [year, setYear] = useState("");
  const [featured, setFeatured] = useState<string[]>([]);

  const missing = [!category && "category", !video && "video", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell title="Performance" missing={missing}>
      <Section title="Category">
        <SelectRow label="Category" value={category} options={PERFORMANCE_CATEGORIES} placeholder="Select Category" onChange={setCategory} />
      </Section>

      {category && (
        <>
          <Section title="Upload">
            <FileRow noun="video" accept="video/*" file={video} onChange={setVideo} icon={<VideoIcon />} />
            <FileRow noun="thumbnail" accept="image/*" file={thumbnail} onChange={setThumbnail} optional />
            <MoreRows>
              <FilesRow noun="headshots" accept="image/*" files={headshots} onChange={setHeadshots} optional />
              <FileRow noun="resume" accept="application/pdf,image/*" file={resume} onChange={setResume} icon={<FileIcon />} optional />
            </MoreRows>
          </Section>

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder="Title" />
            <TextArea value={description} onChange={setDescription} placeholder="Description" />
            <SelectRow label="Release Year" value={year} options={releaseYears()} onChange={setYear} />
          </Section>

          <Section title="Other" footer="Projects you're in that this reel draws from.">
            <ListRow label="Featured Work" items={featured} onChange={setFeatured} placeholder="Project name" addLabel="Add project" />
          </Section>
        </>
      )}
    </SubmissionShell>
  );
}
