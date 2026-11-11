"use client";

import { useState } from "react";
import { CREW_ROLES, PROJECT_CATEGORIES, SCRIPT_GENRES, type ProjectCategory } from "@/lib/shareOptions";
import { extension, image, pdfPageCount, raw } from "@/lib/shareUpload";
import { CreditsRow, DateRow, FileIcon, FileRow, FilesRow, ListRow, Section, SelectRow, TextArea, TextInput, filledCredits, seedCredits } from "../FormKit";
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

  // No category yet shows the Cast & Crew Call fields, the most general layout.
  const layout: ProjectCategory = category || "Cast & Crew Call";
  const isScript = layout === "Script";
  const isCall = layout === "Cast & Crew Call";

  const missing = [
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
    <SubmissionShell
      type="project"
      title="Project"
      missing={missing}
      draft={async () => {
        // Dates are local days; the timestamps are their midnight in the poster's time zone.
        const at = (day: string) => (day ? new Date(`${day}T00:00:00`).getTime() : 0);
        return {
          type: "project",
          text: {
            title,
            logline,
            category,
            writers: isCall ? "" : writers,
            shootStart: isCall ? shootStart : "",
            shootEnd: isCall ? shootEnd : "",
            release: isCall ? release : "",
            scriptExt: script ? extension(script, "pdf") : "",
          },
          lists: {
            genres: isScript && genre ? [genre] : [],
            castNeeded: isCall ? castNeeded : [],
            crewNeeded: isCall ? crewNeeded : [],
            castAssembled: isScript ? [] : castAssembled,
          },
          credits: { crewAssembled: isScript ? [] : filledCredits(crewAssembled) },
          numbers: {
            shootStartAt: isCall ? at(shootStart) : 0,
            releaseAt: isCall ? at(release) : 0,
            scriptPageCount: isScript && script ? await pdfPageCount(script) : 0,
          },
          flags: {},
          files: {
            projectPoster: poster ? [image(poster, 1600)] : [],
            projectSlides: slides.map((f) => image(f)),
            scriptFile: isScript && script ? [raw(script)] : [],
          },
        };
      }}
    >
      <Section title="Category">
        <SelectRow label="Category" value={category} options={PROJECT_CATEGORIES} placeholder="Select Category" onChange={(v) => setCategory(v as ProjectCategory)} />
      </Section>

      <>
          <Section title="Upload" footer="Slides show on the post before the poster. Discover previews the poster.">
            <FileRow noun="poster" accept="image/*" file={poster} onChange={setPoster} optional />
            <FilesRow noun="slides" accept="image/*" files={slides} onChange={setSlides} optional />
          </Section>

          {isCall && (
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

          {isScript && (
            <Section title="Details">
              <TextInput value={title} onChange={setTitle} placeholder="Title" />
              <FileRow noun="script" accept="application/pdf,.pdf,.txt,.rtf,.fdx" file={script} onChange={setScript} icon={<FileIcon />} />
              <SelectRow label="Genre" value={genre} options={SCRIPT_GENRES} onChange={setGenre} />
              <TextInput value={writers} onChange={setWriters} placeholder="Writer" />
              <TextArea value={logline} onChange={setLogline} placeholder="Logline (optional)" maxLength={500} />
            </Section>
          )}

          {layout === "In-Development" && (
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
    </SubmissionShell>
  );
}
