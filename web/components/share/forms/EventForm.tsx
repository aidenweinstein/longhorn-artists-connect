"use client";

import { useState } from "react";
import { EVENT_CATEGORIES, eventRules, type EventCategory } from "@/lib/shareOptions";
import { DateRow, FileRow, Section, SelectRow, TextArea, TextInput } from "../FormKit";
import SubmissionShell from "../SubmissionShell";

type Showing = { day: string; start: string; end: string };
const emptyShowing = (): Showing => ({ day: "", start: "19:00", end: "21:00" });

export default function EventForm() {
  const [category, setCategory] = useState<EventCategory | "">("");
  const [flyer, setFlyer] = useState<File | null>(null);
  const [title, setTitle] = useState("");
  const [host, setHost] = useState("");
  const [description, setDescription] = useState("");
  const [day, setDay] = useState("");
  const [startTime, setStartTime] = useState("18:00");
  const [endTime, setEndTime] = useState("20:00");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [showings, setShowings] = useState<Showing[]>([emptyShowing()]);
  const [location, setLocation] = useState("");
  const [lineup, setLineup] = useState("");
  const [expectations, setExpectations] = useState("");
  const [applicationLink, setApplicationLink] = useState("");
  const [ticketLink, setTicketLink] = useState("");

  const rules = category ? eventRules(category) : null;

  const missing = rules
    ? ([
        !title.trim() && "title",
        !host.trim() && "host",
        rules.usesDateTime && !day && "date",
        rules.usesDateRange && !startDate && "start date",
        rules.usesShowings && !showings.some((s) => s.day) && "a showing date",
        rules.showsLocation && !location.trim() && "location",
      ].filter(Boolean) as string[])
    : ["category"];

  const updateShowing = (i: number, patch: Partial<Showing>) => setShowings((all) => all.map((s, j) => (j === i ? { ...s, ...patch } : s)));

  return (
    <SubmissionShell title="Event" missing={missing}>
      <Section title="Category">
        <SelectRow label="Category" value={category} options={EVENT_CATEGORIES} placeholder="Select Category" onChange={(v) => setCategory(v as EventCategory)} />
      </Section>

      {rules && (
        <>
          <Section title="Upload">
            <FileRow noun="flyer" accept="image/*" file={flyer} onChange={setFlyer} optional />
          </Section>

          <Section title="Details">
            <TextInput value={title} onChange={setTitle} placeholder="Title" />
            <TextInput value={host} onChange={setHost} placeholder="Host" />
            <TextArea value={description} onChange={setDescription} placeholder="Description" />
          </Section>

          <Section title={rules.usesShowings ? "Showings" : "When & Where"}>
            {rules.usesDateRange && (
              <>
                <DateRow label="Start Date" value={startDate} onChange={setStartDate} />
                <DateRow label="End Date" value={endDate} onChange={setEndDate} min={startDate || undefined} />
              </>
            )}
            {rules.usesDateTime && (
              <>
                <DateRow label="Date" value={day} onChange={setDay} />
                <DateRow label="Start Time" type="time" value={startTime} onChange={setStartTime} />
                <DateRow label="End Time" type="time" value={endTime} onChange={setEndTime} />
              </>
            )}
            {rules.usesShowings &&
              showings.map((s, i) => (
                <div key={i} className="divide-y divide-border">
                  <div className="flex items-center justify-between px-4 pt-3 text-sm font-semibold">
                    Showing {i + 1}
                    {showings.length > 1 && (
                      <button type="button" onClick={() => setShowings((all) => all.filter((_, j) => j !== i))} className="font-normal text-muted hover:text-foreground">
                        Remove
                      </button>
                    )}
                  </div>
                  <DateRow label="Date" value={s.day} onChange={(v) => updateShowing(i, { day: v })} />
                  <DateRow label="Start Time" type="time" value={s.start} onChange={(v) => updateShowing(i, { start: v })} />
                  <DateRow label="End Time" type="time" value={s.end} onChange={(v) => updateShowing(i, { end: v })} />
                </div>
              ))}
            {rules.usesShowings && (
              <button type="button" onClick={() => setShowings((all) => [...all, emptyShowing()])} className="w-full px-4 py-3 text-left text-[15px] text-brand">
                + Add showing
              </button>
            )}
            {rules.showsLocation && <TextInput value={location} onChange={setLocation} placeholder="Location" />}
          </Section>

          {(rules.lineupLabel || rules.showsExpectations || rules.showsApplicationLink || rules.showsTicketLink) && (
            <Section title="More">
              {rules.lineupLabel && <TextArea value={lineup} onChange={setLineup} placeholder={rules.lineupLabel} rows={2} />}
              {rules.showsExpectations && <TextArea value={expectations} onChange={setExpectations} placeholder="What to expect" />}
              {rules.showsApplicationLink && <TextInput type="url" value={applicationLink} onChange={setApplicationLink} placeholder="Application Link" />}
              {rules.showsTicketLink && <TextInput type="url" value={ticketLink} onChange={setTicketLink} placeholder="Ticket Link" />}
            </Section>
          )}
        </>
      )}
    </SubmissionShell>
  );
}
