"use client";

import { useState } from "react";
import { CREW_ROLES, PROJECT_CATEGORIES, SCRIPT_GENRES, type ProjectCategory } from "@/lib/shareOptions";
import { CreditsRow, DateRow, FileIcon, FileRow, FilesRow, ListRow, Section, SelectRow, TextArea, TextInput, seedCredits } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

export default function ProjectForm() {
  const [category, setCategory] = useState<ProjectCategory | "">("");
  const [poster, setPoster] = useState<File | null>(null);
  const [slides, setSlides] = useState<File[]>([]);
  const [script, setScript] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [logline, setLogline] = useState("");
  const [writers, setWriters] = useState("");
  const [genre, setGenre] = useState("");
  const [shootStart, setShootStart] = useState("");
  const [shootEnd, setShootEnd] = useState("");
  const [release, setRelease] = useState("");
  const [castNeeded, setCastNeeded] = useState<string[]>([""]);
  const [crewNeeded, setCrewNeeded] = useState<string[]>([""]);
  const [castAssembled, setCastAssembled] = useState<string[]>([""]);
  const [crewAssembled, setCrewAssembled] = useState(() => seedCredits(CREW_ROLES));

  const missing = [
    !category && "category",
    !title.trim() && "title",
    category === "Script" && !script && "script",
    category === "Cast & Crew Call" && !shootStart && "shoot start",
  ].filter(Boolean) as string[];

  const assembledTeam = (
    <Section title="Assembled Team">
      <ListRow label="Cast Assembled" items={castAssembled} onChange={setCastAssembled} placeholder="Actor name" addLabel="Add cast member" />
      <CreditsRow label="Crew Assembled" credits={crewAssembled} onChange={setCrewAssembled} />
    </Section>
  );

  return (
    <SubmissionShell title="Project" missing={missing}>
      <Section title="Category">
        <SelectRow label="Category" value={category} options={PROJECT_CATEGORIES} placeholder="Select Category" onChange={(v) => setCategory(v as ProjectCategory)} />
      </Section>

      {category && (
        <>
          <Section title="Upload" footer="Slides show on the post before the poster. Discover previews the poster.">
            <FileRow noun="poster" accept="image/*" file={poster} onChange={setPoster} optional />
            <FilesRow noun="slides" accept="image/*" files={slides} onChange={setSlides} optional />
          </Section>

          {category === "Cast & Crew Call" && (
            <>
              <Section title="Details">
                <TextInput value={title} onChange={setTitle} placeholder="Title" />
                <TextArea value={logline} onChange={setLogline} placeholder="Logline" maxLength={500} />
                <DateRow label="Shoot Start" value={shootStart} onChange={setShootStart} />
                <DateRow label="Shoot End" value={shootEnd} onChange={setShootEnd} min={shootStart || undefined} />
                <DateRow label="Expected Release" value={release} onChange={setRelease} min={shootEnd || shootStart || undefined} />
              </Section>
              <Section title="Team Needed">
                <ListRow label="Cast Needed" items={castNeeded} onChange={setCastNeeded} placeholder="Role (e.g., Lead Actor)" addLabel="Add available role" />
                <ListRow label="Crew Needed" items={crewNeeded} onChange={setCrewNeeded} placeholder="Role (e.g., Sound Mixer)" addLabel="Add available role" />
              </Section>
              {assembledTeam}
            </>
          )}

          {category === "Script" && (
            <Section title="Details">
              <TextInput value={title} onChange={setTitle} placeholder="Title" />
              <FileRow noun="script" accept="application/pdf,.pdf,.txt,.rtf,.fdx" file={script} onChange={setScript} icon={<FileIcon />} />
              <SelectRow label="Genre" value={genre} options={SCRIPT_GENRES} onChange={setGenre} />
              <TextInput value={writers} onChange={setWriters} placeholder="Writer" />
              <TextArea value={logline} onChange={setLogline} placeholder="Logline (optional)" maxLength={500} />
            </Section>
          )}

          {category === "In-Development" && (
            <>
              <Section title="Details">
                <TextInput value={title} onChange={setTitle} placeholder="Title" />
                <TextInput value={writers} onChange={setWriters} placeholder="Writers" />
                <TextArea value={logline} onChange={setLogline} placeholder="Logline (optional)" maxLength={500} />
              </Section>
              {assembledTeam}
            </>
          )}
        </>
      )}
    </SubmissionShell>
  );
}
