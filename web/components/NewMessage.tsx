"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useRef, useState, useTransition } from "react";
import { startConversationAction } from "@/app/(app)/network/actions";
import { preparePhoto } from "@/lib/preparePhoto";
import Avatar from "./Avatar";
import { CameraGlyph } from "./icons";

export type Recipient = {
  profileID: string;
  name: string;
  imageUrl?: string;
  roles: string[];
  school?: string;
  /** Connected with the visitor: suggested before anyone else. */
  connected: boolean;
};

const MAX_RESULTS = 30;

/**
 * Network → New message. A "To:" field that takes one or more people as chips: one
 * person opens a 1:1 chat, two or more make a group (with an optional name and photo). Sending
 * the first message creates the thread and opens it in the inbox.
 */
export default function NewMessage({ people, preset = [] }: { people: Recipient[]; preset?: string[] }) {
  const router = useRouter();
  const [picked, setPicked] = useState<string[]>(preset);
  const [query, setQuery] = useState("");
  const [focused, setFocused] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const [groupName, setGroupName] = useState("");
  /** The group's picture, shrunk and ready to send, with a preview URL. */
  const [photo, setPhoto] = useState<{ file: File; url: string } | null>(null);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, startSend] = useTransition();
  const search = useRef<HTMLInputElement>(null);
  const message = useRef<HTMLTextAreaElement>(null);

  const byID = useMemo(() => new Map(people.map((p) => [p.profileID, p])), [people]);
  const chosen = picked.flatMap((id) => byID.get(id) ?? []);
  const isGroup = chosen.length >= 2;

  // Matches on name, role or school; connections first, then alphabetical.
  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const pool = people.filter((p) => !picked.includes(p.profileID));
    const hits = q
      ? pool.filter((p) => p.name.toLowerCase().includes(q) || p.roles.some((r) => r.toLowerCase().includes(q)) || p.school?.toLowerCase().includes(q))
      : pool.filter((p) => p.connected);
    return hits
      .sort((a, b) => {
        if (q) {
          // Names that start with what was typed come first.
          const sa = a.name.toLowerCase().startsWith(q) ? 0 : 1;
          const sb = b.name.toLowerCase().startsWith(q) ? 0 : 1;
          if (sa !== sb) return sa - sb;
        }
        return Number(b.connected) - Number(a.connected) || a.name.localeCompare(b.name);
      })
      .slice(0, MAX_RESULTS);
  }, [people, picked, query]);

  function add(p: Recipient) {
    setPicked((ids) => (ids.includes(p.profileID) ? ids : [...ids, p.profileID]));
    setQuery("");
    setHighlight(0);
    setError(null);
    search.current?.focus();
  }

  function remove(id: string) {
    setPicked((ids) => ids.filter((x) => x !== id));
    search.current?.focus();
  }

  async function choosePhoto(file: File | undefined) {
    if (!file) return;
    setError(null);
    try {
      const ready = await preparePhoto(file, 800, "group.jpg");
      setPhoto({ file: ready, url: URL.createObjectURL(ready) });
    } catch {
      setError("That photo couldn't be read. Try a JPEG or PNG.");
    }
  }

  function send() {
    const text = draft.trim();
    if (sending) return;
    if (picked.length === 0) return setError("Add someone to message.");
    if (!text) return setError("Write a message first.");
    setError(null);
    startSend(async () => {
      let photoForm: FormData | undefined;
      if (isGroup && photo) {
        photoForm = new FormData();
        photoForm.set("photo", photo.file);
      }
      const res = await startConversationAction(picked, text, isGroup ? groupName : undefined, photoForm);
      if (!res.ok) return setError(res.message);
      router.push(`/network?c=${encodeURIComponent(res.threadID)}`);
      router.refresh();
    });
  }

  const showResults = focused && (query.trim() !== "" || results.length > 0);

  return (
    <div className="flex h-[calc(100dvh-7rem)] min-h-[420px] min-w-0 flex-col overflow-hidden rounded-2xl border border-border">
      <header className="flex items-center gap-3 border-b border-border px-4 py-3">
        <Link href="/network" className="text-sm font-semibold text-brand">
          ‹ Back
        </Link>
        <p className="flex-1 text-center font-semibold">{isGroup ? "New group" : "New message"}</p>
        {/* Balances Back so the title stays centred. */}
        <span className="invisible text-sm font-semibold">‹ Back</span>
      </header>

      {/* To: */}
      <div className="relative border-b border-border">
        <div className="flex flex-wrap items-center gap-1.5 px-4 py-2.5" onClick={() => search.current?.focus()}>
          <span className="mr-1 text-sm text-muted">To:</span>
          {chosen.map((p) => (
            <span key={p.profileID} className="flex items-center gap-1.5 rounded-full bg-brand/10 py-0.5 pl-0.5 pr-2 text-sm font-medium text-brand">
              <Avatar name={p.name} src={p.imageUrl} size="sm" />
              {p.name}
              <button
                type="button"
                aria-label={`Remove ${p.name}`}
                onClick={(e) => {
                  e.stopPropagation();
                  remove(p.profileID);
                }}
                className="ml-0.5 text-base leading-none opacity-70 hover:opacity-100"
              >
                ×
              </button>
            </span>
          ))}
          <input
            ref={search}
            value={query}
            autoFocus={preset.length === 0}
            onChange={(e) => {
              setQuery(e.target.value);
              setHighlight(0);
            }}
            onFocus={() => setFocused(true)}
            // Delay so a click on a result lands before the list closes.
            onBlur={() => setTimeout(() => setFocused(false), 150)}
            onKeyDown={(e) => {
              if (e.key === "Backspace" && !query && picked.length) {
                setPicked((ids) => ids.slice(0, -1));
              } else if (e.key === "ArrowDown") {
                e.preventDefault();
                setHighlight((h) => Math.min(h + 1, results.length - 1));
              } else if (e.key === "ArrowUp") {
                e.preventDefault();
                setHighlight((h) => Math.max(h - 1, 0));
              } else if (e.key === "Enter") {
                e.preventDefault();
                if (results[highlight]) add(results[highlight]);
                else if (!query && picked.length) message.current?.focus();
              }
            }}
            placeholder={picked.length ? "Add more people" : "Search people by name, role or school"}
            className="min-w-[10rem] flex-1 bg-transparent py-1 text-sm outline-none"
          />
        </div>

        {showResults && (
          <ul className="absolute inset-x-0 top-full z-20 max-h-80 overflow-y-auto border-b border-border bg-background shadow-lg">
            {!query.trim() && <li className="px-4 pb-1 pt-3 text-xs font-semibold uppercase tracking-wide text-muted">Your connections</li>}
            {results.length === 0 && <li className="px-4 py-4 text-sm text-muted">No one on Nexus matches “{query.trim()}”.</li>}
            {results.map((p, i) => (
              <li key={p.profileID}>
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onMouseEnter={() => setHighlight(i)}
                  onClick={() => add(p)}
                  className={`flex w-full items-center gap-3 px-4 py-2 text-left ${i === highlight ? "bg-surface" : ""}`}
                >
                  <Avatar name={p.name} src={p.imageUrl} size="md" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-medium">{p.name}</span>
                    {(p.roles.length > 0 || p.school) && (
                      <span className="block truncate text-xs text-muted">{[p.roles.join(", "), p.school].filter(Boolean).join(" · ")}</span>
                    )}
                  </span>
                  {p.connected && query.trim() && <span className="shrink-0 text-xs text-muted">Connected</span>}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* Group photo and name, once there are two or more people. */}
      {isGroup && (
        <div className="flex items-center gap-2 border-b border-border px-4 py-2.5">
          <label title={photo ? "Change group photo" : "Add group photo"} className="group mr-1 shrink-0 cursor-pointer rounded-full">
            {photo ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={photo.url} alt="" className="h-9 w-9 rounded-full object-cover" />
            ) : (
              <span className="flex h-9 w-9 items-center justify-center rounded-full border border-dashed border-border text-muted transition group-hover:border-brand group-hover:text-brand">
                <CameraGlyph className="h-[18px] w-[18px]" />
              </span>
            )}
            <span className="sr-only">{photo ? "Change group photo" : "Add group photo"}</span>
            <input
              type="file"
              accept="image/jpeg,image/png,image/heic,image/*"
              className="sr-only"
              onChange={(e) => {
                choosePhoto(e.target.files?.[0]);
                e.target.value = "";
              }}
            />
          </label>
          <span className="text-sm text-muted">Name:</span>
          <input
            value={groupName}
            maxLength={100}
            onChange={(e) => setGroupName(e.target.value)}
            placeholder={`Optional (${chosen.length + 1} people)`}
            className="min-w-0 flex-1 bg-transparent py-1 text-sm outline-none"
          />
          {photo && (
            <button type="button" onClick={() => setPhoto(null)} className="shrink-0 text-xs text-muted hover:text-foreground">
              Remove photo
            </button>
          )}
        </div>
      )}

      {/* Who it's going to, until the first message is sent. */}
      <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-3 overflow-y-auto p-6 text-center">
        {chosen.length === 0 ? (
          <p className="max-w-xs text-sm text-muted">Add one person for a direct message, or a few people to start a group chat.</p>
        ) : (
          <>
            {isGroup && photo ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={photo.url} alt="" className="h-20 w-20 rounded-full object-cover" />
            ) : (
            <div className="flex -space-x-3">
              {chosen.slice(0, 5).map((p) => (
                <span key={p.profileID} className="rounded-full ring-2 ring-background">
                  <Avatar name={p.name} src={p.imageUrl} size="lg" />
                </span>
              ))}
            </div>
            )}
            <p className="font-semibold">{isGroup ? groupName.trim() || chosen.map((p) => p.name.split(" ")[0]).join(", ") : chosen[0].name}</p>
            {isGroup && <p className="text-xs text-muted">You and {chosen.length} others</p>}
          </>
        )}
      </div>

      <form
        className="border-t border-border p-3"
        onSubmit={(e) => {
          e.preventDefault();
          send();
        }}
      >
        {error && <p className="mb-2 text-sm text-red-500">{error}</p>}
        <div className="flex items-end gap-2">
          <textarea
            ref={message}
            value={draft}
            rows={1}
            maxLength={4000}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              // Enter sends; Shift+Enter makes a new line.
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                send();
              }
            }}
            placeholder={isGroup ? "Message the group" : chosen[0] ? `Message ${chosen[0].name.split(" ")[0]}` : "Message"}
            className="max-h-40 min-w-0 flex-1 resize-none rounded-2xl border border-border bg-background px-4 py-2 text-sm outline-none focus:border-brand"
          />
          <button
            type="submit"
            disabled={!picked.length || !draft.trim() || sending}
            className="rounded-full bg-brand px-4 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-50"
          >
            {sending ? "…" : "Send"}
          </button>
        </div>
      </form>
    </div>
  );
}
