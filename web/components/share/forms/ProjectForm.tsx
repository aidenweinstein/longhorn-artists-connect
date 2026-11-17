"use client";

import { CREW_ROLES, PROJECT_CATEGORIES, SCRIPT_GENRES, type ProjectCategory } from "@/lib/shareOptions";
import { extension, image, pdfPageCount, raw } from "@/lib/shareUpload";
import { CreditsRow, DateRow, FileIcon, FileRow, FilesRow, ListRow, Section, SelectRow, TextArea, TextInput, filledCredits, seedCredits, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

export default function ProjectForm() {
  const [category, setCategory] = useDraftField<ProjectCategory | "">("category", "");
  const [poster, setPoster] = useDraftField<File | null>("poster", null);
  const [slides, setSlides] = useDraftField<File[]>("slides", []);
  const [script, setScript] = useDraftField<File | null>("script", null);
  const [title, setTitle] = useDraftField("title", "");
  const [logline, setLogline] = useDraftField("logline", "");
  const [writers, setWriters] = useDraftField("writers", "");
  const [genre, setGenre] = useDraftField("genre", "");
  const [shootStart, setShootStart] = useDraftField("shootStart", "");
  const [shootEnd, setShootEnd] = useDraftField("shootEnd", "");
  const [release, setRelease] = useDraftField("release", "");
  const [castNeeded, setCastNeeded] = useDraftField<string[]>("castNeeded", [""]);
  const [crewNeeded, setCrewNeeded] = useDraftField<string[]>("crewNeeded", [""]);
  const [castAssembled, setCastAssembled] = useDraftField<Credit[]>("castAssembled", [{ role: "", name: "" }]);
  const [crewAssembled, setCrewAssembled] = useDraftField("crewAssembled", () => seedCredits(CREW_ROLES));

  // No category yet shows the Cast & Crew Call fields, the most general layout.
  const layout: ProjectCategory = category || "Cast & Crew Call";
  const isScript = layout === "Script";
  const isCall = layout === "Cast & Crew Call";

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [
    !title.trim() && "title",
    category === "Script" && !script && !kept.has("script") && "script",
    category === "Cast & Crew Call" && !shootStart && "shoot start",
  ].filter(Boolean) as string[];

  const assembledTeam = (
    <Section title="Assembled Team">
      <CreditsRow label="Cast Assembled" credits={castAssembled} onChange={setCastAssembled} rolePlaceholder="Role" namePlaceholder="Actor" addLabel="Add cast member" />
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
          },
          credits: {
            castAssembled: isScript ? [] : filledCredits(castAssembled),
            crewAssembled: isScript ? [] : filledCredits(crewAssembled),
          },
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
