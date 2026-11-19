"use client";

import { useEffect, useId, useRef, useState, useTransition } from "react";
import { getEditors, setEditors, type Editor } from "@/app/(app)/share/editActions";
import type { PersonMatch } from "@/lib/sharePost";

/**
 * "Edit access" on a post's page, for the person who posted it: the people who can edit
 * the post too. Adding or removing someone saves right away. Editors can change the post
 * and its files, but only the person who posted it can delete it or change this list.
 */
export default function EditAccess({ postID }: { postID: string }) {
  const [open, setOpen] = useState(false);
  const [editors, setList] = useState<Editor[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const box = useRef<HTMLDivElement>(null);

  // Read the current list each time the panel opens.
  useEffect(() => {
    if (!open) return;
    let live = true;
    getEditors(postID).then(
      (res) => {
        if (!live) return;
        if (res.ok) setList(res.editors);
        else setError(res.message);
      },
      () => live && setError("Couldn't load who can edit this. Try again in a moment."),
    );
    return () => {
      live = false;
    };
  }, [open, postID]);

  // Closes on a click outside the panel, or Escape.
  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => box.current && !box.current.contains(e.target as Node) && setOpen(false);
    const esc = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", away);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("mousedown", away);
      document.removeEventListener("keydown", esc);
    };
  }, [open]);

  function save(next: Editor[]) {
    const before = editors;
    setList(next);
    setError(null);
    start(async () => {
      const res = await setEditors(postID, next.map((e) => e.id)).catch(() => null);
      if (res?.ok) setList(res.editors);
      else {
        setList(before);
        setError(res?.message ?? "Couldn't save who can edit this. Try again in a moment.");
      }
    });
  }

  return (
    <div ref={box} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="inline-flex items-center gap-1.5 rounded-full border border-border px-4 py-1.5 text-sm font-semibold hover:bg-foreground/5"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM19 8v6M22 11h-6" />
        </svg>
        Edit access
      </button>

      {open && (
        <div className="absolute right-0 top-full z-30 mt-2 w-[min(24rem,calc(100vw-2rem))] space-y-3 rounded-2xl border border-border bg-surface p-4 shadow-xl">
          <div>
            <p className="font-semibold">Who can edit this</p>
            <p className="mt-0.5 text-sm text-muted">They can change the details and files. Only you can delete it or change this list.</p>
          </div>

          <PersonSearch
            exclude={new Set((editors ?? []).map((e) => e.id))}
            disabled={editors === null}
            onPick={(p) => save([...(editors ?? []), { id: p.id, name: p.name, imageUrl: p.imageUrl }])}
          />

          {editors === null && !error ? (
            <p className="text-sm text-muted">Loading…</p>
          ) : editors && editors.length > 0 ? (
            <ul className="space-y-1">
              {editors.map((e) => (
                <li key={e.id} className="flex items-center gap-3 rounded-xl px-1 py-1.5">
                  <Avatar name={e.name} url={e.imageUrl} />
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{e.name}</span>
                  <button
                    type="button"
                    onClick={() => save(editors.filter((x) => x.id !== e.id))}
                    disabled={pending}
                    className="rounded-full px-3 py-1 text-xs font-semibold text-muted hover:bg-foreground/10 hover:text-foreground disabled:opacity-50"
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            editors && <p className="text-sm text-muted">Only you can edit this post right now.</p>
          )}

          {error && <p className="text-sm text-red-500">{error}</p>}
          {pending && <p role="status" className="text-xs text-muted">Saving…</p>}
        </div>
      )}
    </div>
  );
}

function Avatar({ name, url }: { name: string; url?: string }) {
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={url} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
  ) : (
    <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-foreground/10 text-xs font-semibold">
      {name.trim().charAt(0).toUpperCase() || "?"}
    </span>
  );
}

/** A name box that suggests Nexus members as you type (the same lookup as the Share forms' credits). */
function PersonSearch({ exclude, disabled, onPick }: { exclude: ReadonlySet<string>; disabled: boolean; onPick: (p: PersonMatch) => void }) {
  const listId = useId();
  const [text, setText] = useState("");
  const [people, setPeople] = useState<PersonMatch[]>([]);
  const [active, setActive] = useState(0);
  const query = text.trim();

  useEffect(() => {
    if (query.length < 2) return;
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/people?q=${encodeURIComponent(query)}`, { signal: abort.signal });
        if (!res.ok) return;
        const body = (await res.json()) as { people: PersonMatch[] };
        setPeople(body.people);
        setActive(0);
      } catch {
        // Nothing to suggest; try typing again.
      }
    }, 150);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query]);

  const shown = query.length >= 2 ? people.filter((p) => !exclude.has(p.id)) : [];
  const pick = (p: PersonMatch) => {
    onPick(p);
    setText("");
    setPeople([]);
  };

  return (
    <div className="relative">
      <input
        role="combobox"
        aria-label="Add a person by name"
        aria-expanded={shown.length > 0}
        aria-controls={listId}
        aria-autocomplete="list"
        autoComplete="off"
        autoFocus
        disabled={disabled}
        value={text}
        placeholder="Add someone by name"
        onChange={(e) => setText(e.target.value)}
        onKeyDown={(e) => {
          if (!shown.length) return;
          if (e.key === "ArrowDown" || e.key === "ArrowUp") {
            e.preventDefault();
            setActive((a) => (a + (e.key === "ArrowDown" ? 1 : shown.length - 1)) % shown.length);
          } else if (e.key === "Enter") {
            e.preventDefault();
            pick(shown[active] ?? shown[0]);
          }
        }}
        className="w-full rounded-xl border border-border bg-background px-3 py-2 text-sm outline-none focus:border-brand disabled:opacity-60"
      />
      {shown.length > 0 && (
        <ul id={listId} role="listbox" className="absolute left-0 right-0 top-full z-40 mt-1 overflow-hidden rounded-xl border border-border bg-surface shadow-lg">
          {shown.map((p, i) => (
            <li
              key={p.id}
              role="option"
              aria-selected={i === active}
              onMouseDown={(e) => {
                e.preventDefault();
                pick(p);
              }}
              onMouseEnter={() => setActive(i)}
              className={`flex cursor-pointer items-center gap-3 px-3 py-2 ${i === active ? "bg-foreground/10" : ""}`}
            >
              <Avatar name={p.name} url={p.imageUrl} />
              <span className="min-w-0">
                <span className="block truncate text-sm font-medium">{p.name}</span>
                {p.subtitle && <span className="block truncate text-xs text-muted">{p.subtitle}</span>}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
