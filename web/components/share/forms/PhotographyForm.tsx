"use client";

import { PHOTO_EQUIPMENT } from "@/lib/shareOptions";
import { image } from "@/lib/shareUpload";
import { useReleaseYears, CreditsRow, DisclosureRow, FilesRow, Section, SelectRow, SubField, TextArea, TextInput, subInput, type Credit } from "../FormKit";
import { useDraftField, useKeptFiles } from "../DraftContext";
import SubmissionShell from "../SubmissionShell";

type Equipment = Record<(typeof PHOTO_EQUIPMENT)[number]["key"], string>;

export default function PhotographyForm() {
  const years = useReleaseYears();
  const [photos, setPhotos] = useDraftField<File[]>("photos", []);
  const [title, setTitle] = useDraftField("title", "");
  const [description, setDescription] = useDraftField("description", "");
  const [year, setYear] = useDraftField("year", "");
  const [credits, setCredits] = useDraftField<Credit[]>("credits", [{ role: "Photographer", name: "" }, { role: "Model", name: "" }]);
  const [equipment, setEquipment] = useDraftField<Equipment>("equipment", { camera: "", lens: "", lighting: "", filters: "", support: "", accessories: "" });

  // Editing: files the post already has count as there.
  const kept = useKeptFiles();
  const missing = [!photos.length && !kept.has("photos") && "photos", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell
      type="photography"
      title="Photography"
      missing={missing}
      draft={() => ({
        type: "photography",
        text: { title, description, releaseYear: year },
        // The app's photographyGear entries: "Label: value", "Other" for other equipment.
        lists: {
          gear: PHOTO_EQUIPMENT.filter((e) => equipment[e.key].trim()).map(
            (e) => `${e.key === "accessories" ? "Other" : e.label}: ${equipment[e.key].trim()}`,
          ),
        },
        credits: { credits: credits.filter((c) => c.name.trim()) },
        numbers: {},
        flags: {},
        files: {
          photographyImages: photos.map((f) => image(f)),
          photographyThumbnail: photos[0] ? [image(photos[0], 1000)] : [],
        },
      })}
    >
      <Section title="Upload" footer="The first photo is the cover.">
        <FilesRow noun="photos" accept="image/*" files={photos} onChange={setPhotos} />
      </Section>

      <Section title="Details">
        <TextInput value={title} onChange={setTitle} placeholder="Title" />
        <TextArea value={description} onChange={setDescription} placeholder="Description" />
        <SelectRow label="Release Year" value={year} options={years} onChange={setYear} />
        <CreditsRow label="Credits" credits={credits} onChange={setCredits} addLabel="Add credit" />
        <DisclosureRow label="Equipment" edited={Object.values(equipment).some((v) => v.trim())}>
          {PHOTO_EQUIPMENT.map((e) => (
            <SubField key={e.key} label={e.label}>
              <input
                className={subInput}
                placeholder={e.placeholder}
                value={equipment[e.key]}
                onChange={(ev) => setEquipment((cur) => ({ ...cur, [e.key]: ev.target.value }))}
              />
            </SubField>
          ))}
        </DisclosureRow>
      </Section>
    </SubmissionShell>
  );
}
