"use client";

import { useState } from "react";
import { PHOTO_EQUIPMENT, releaseYears } from "@/lib/shareOptions";
import { CreditsRow, DisclosureRow, FilesRow, Section, SelectRow, SubField, TextArea, TextInput, subInput, type Credit } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

type Equipment = Record<(typeof PHOTO_EQUIPMENT)[number]["key"], string>;

export default function PhotographyForm() {
  const [photos, setPhotos] = useState<File[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [year, setYear] = useState("");
  const [credits, setCredits] = useState<Credit[]>([{ role: "Photographer", name: "" }, { role: "Model", name: "" }]);
  const [equipment, setEquipment] = useState<Equipment>({ camera: "", lens: "", lighting: "", filters: "", support: "", accessories: "" });

  const missing = [!photos.length && "photos", !title.trim() && "title"].filter(Boolean) as string[];

  return (
    <SubmissionShell title="Photography" missing={missing}>
      <Section title="Upload" footer="The first photo is the cover.">
        <FilesRow noun="photos" accept="image/*" files={photos} onChange={setPhotos} />
      </Section>

      <Section title="Details">
        <TextInput value={title} onChange={setTitle} placeholder="Title" />
        <TextArea value={description} onChange={setDescription} placeholder="Description" />
        <SelectRow label="Release Year" value={year} options={releaseYears()} onChange={setYear} />
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
