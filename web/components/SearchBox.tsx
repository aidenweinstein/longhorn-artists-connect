"use client";

import Link from "next/link";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useEffect, useId, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import { MIN_QUERY_LENGTH, type SearchResult } from "@/lib/search";
import { SearchGlyph } from "./icons";

/** Row height in px; the list shows five rows and scrolls for the rest. */
const ROW = 56;
const VISIBLE_ROWS = 5;

function Thumb({ result }: { result: SearchResult }) {
  const round = result.kind === "artist";
  const shape = round ? "rounded-full" : "rounded-md";
  if (result.imageUrl) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={result.imageUrl} alt="" loading="lazy" className={`h-10 w-10 shrink-0 object-cover bg-surface ${shape}`} />;
  }
  const initials = result.title
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, round ? 2 : 1)
    .map((w) => w[0]?.toUpperCase())
    .join("");
  return (
    <span className={`flex h-10 w-10 shrink-0 items-center justify-center bg-surface text-sm font-semibold text-muted ${shape}`}>
      {initials || "?"}
    </span>
  );
}

/** The top bar's search field, with autofill suggestions beneath it after three characters. */
export default function SearchBox() {
  const pathname = usePathname();
  const params = useSearchParams();
  const router = useRouter();
  const listID = useId();
  const [query, setQuery] = useState(params.get("q") ?? "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loadedFor, setLoadedFor] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const boxRef = useRef<HTMLFormElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  const trimmed = query.trim();
  const ready = trimmed.length >= MIN_QUERY_LENGTH;

  // Fetch suggestions shortly after typing stops; drop answers to older queries.
  useEffect(() => {
    if (!ready) return;
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const res = await fetch(`/api/search?${new URLSearchParams({ q: trimmed, from: pathname })}`, {
          signal: controller.signal,
        });
        const data: { results?: SearchResult[] } = res.ok ? await res.json() : {};
        setResults(data.results ?? []);
        setLoadedFor(trimmed);
        setActive(-1);
      } catch {
        // Aborted by a newer keystroke, or offline: keep whatever is showing.
      }
    }, 150);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [trimmed, ready, pathname]);

  // Close when clicking anywhere else, and when navigating to another page.
  useEffect(() => {
    function onDown(e: MouseEvent) {
      if (!boxRef.current?.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, []);
  const [openedOn, setOpenedOn] = useState(pathname);
  if (openedOn !== pathname) {
    setOpenedOn(pathname);
    setOpen(false);
  }

  // Keep the highlighted row in view while arrowing through the list.
  useEffect(() => {
    if (active < 0) return;
    listRef.current?.children[active]?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const showList = open && ready && loadedFor !== "" && (results.length > 0 || loadedFor === trimmed);

  function onSearch(e: FormEvent) {
    e.preventDefault();
    if (showList && active >= 0 && results[active]) {
      setOpen(false);
      router.push(results[active].href);
      return;
    }
    setOpen(false);
    const next = new URLSearchParams(params.toString());
    if (trimmed) next.set("q", trimmed);
    else next.delete("q");
    const qs = next.toString();
    router.push(qs ? `${pathname}?${qs}` : pathname);
  }

  function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Escape") {
      setOpen(false);
      return;
    }
    if (!showList || results.length === 0) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((i) => (i + 1) % results.length);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => (i <= 0 ? results.length - 1 : i - 1));
    }
  }

  return (
    <form
      ref={boxRef}
      onSubmit={onSearch}
      role="search"
      className="relative flex flex-1 justify-end max-w-2xl sm:min-w-[120px] sm:justify-start"
    >
      <input
        type="search"
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onKeyDown={onKeyDown}
        placeholder="Search"
        autoComplete="off"
        role="combobox"
        aria-expanded={showList}
        aria-controls={listID}
        aria-autocomplete="list"
        aria-activedescendant={active >= 0 ? `${listID}-${active}` : undefined}
        className="hidden h-10 min-w-0 flex-1 rounded-l-full sm:block border border-white/25 bg-black/20 px-5 text-[15px] text-brand-foreground outline-none placeholder:text-brand-foreground/65 focus:border-brand-foreground/80"
      />
      <button
        type="submit"
        aria-label="Search"
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border sm:w-16 sm:rounded-l-none sm:border-l-0 border-white/25 bg-white/15 text-brand-foreground hover:bg-white/25"
      >
        <SearchGlyph className="h-5 w-5" />
      </button>

      {showList && (
        <div className="absolute left-0 right-0 top-full z-50 mt-2 hidden overflow-hidden rounded-2xl border border-foreground/10 bg-background text-foreground shadow-xl sm:block">
          {results.length === 0 ? (
            <p className="px-4 py-4 text-sm text-muted">No matches for “{loadedFor}”</p>
          ) : (
            <ul
              ref={listRef}
              id={listID}
              role="listbox"
              className="overflow-y-auto overscroll-contain py-1"
              style={{ maxHeight: ROW * VISIBLE_ROWS + 8 }}
            >
              {results.map((r, i) => (
                <li key={`${r.kind}-${r.id}`} id={`${listID}-${i}`} role="option" aria-selected={i === active}>
                  <Link
                    href={r.href}
                    onClick={() => setOpen(false)}
                    onMouseEnter={() => setActive(i)}
                    style={{ height: ROW }}
                    className={`flex items-center gap-3 px-3 ${i === active ? "bg-foreground/[0.06]" : ""}`}
                  >
                    <Thumb result={r} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[15px] font-medium">{r.title}</span>
                      {r.subtitle && <span className="block truncate text-xs text-muted">{r.subtitle}</span>}
                    </span>
                    <span className="shrink-0 rounded-full bg-surface px-2 py-0.5 text-[11px] font-medium text-muted">
                      {r.label}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </form>
  );
}
