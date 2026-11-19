"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { savePortfolioLayout } from "@/app/(app)/portfolio/actions";
import type { Post } from "@/lib/mockContent";
import { TILE_SIZES, type TileSize, type TileSizes } from "@/lib/portfolioLayout";
import { thumbSources } from "@/lib/smallImage";
import { ContentCard, TINT } from "./ContentGrid";
import PagedGrid from "./PagedGrid";

/**
 * How wide each size is. The grid has six columns from tablet width up: on a wide
 * window small is a third, medium a half and large two thirds of the row; on a
 * narrower one small and medium are a half and large is the full row. Phones show
 * one post per row whatever its size.
 */
const SPAN: Record<TileSize, string> = {
  small: "sm:col-span-3 lg:col-span-2",
  medium: "sm:col-span-3 lg:col-span-3",
  large: "sm:col-span-6 lg:col-span-4",
};
const SIZE_LABEL: Record<TileSize, string> = { small: "Small", medium: "Medium", large: "Large" };
/*
 * Rows are only ROW_PX tall, and each tile takes as many rows as its own height needs
 * (useRowSpans), so a tall post such as a poster runs down several rows and the posts
 * after it fill the space beside it instead of leaving a gap under shorter neighbours.
 * The space between rows is each tile's own bottom padding (TILE_GAP), not a row gap.
 */
const ROW_PX = 4;
const GRID = "grid grid-cols-1 items-start gap-x-4 sm:grid-cols-6";
const TILE_GAP = "pb-8";

/**
 * Sizes each tile of the grid at `ref` to the number of ROW_PX rows its height needs,
 * and keeps it right as tiles resize (images load, the window changes, a size changes).
 * Until this runs (before the page's script loads) the grid is plain rows. `deps`
 * changes whenever the tiles or their sizes do, so new tiles are measured.
 */
function useRowSpans<T extends HTMLElement>(deps: string) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const grid = ref.current;
    if (!grid) return;
    const tiles = Array.from(grid.children) as HTMLElement[];
    const fit = (tile: HTMLElement) => {
      const rows = Math.max(1, Math.ceil(tile.getBoundingClientRect().height / ROW_PX));
      tile.style.gridRowEnd = `span ${rows}`;
    };
    grid.style.gridAutoRows = `${ROW_PX}px`;
    tiles.forEach(fit);
    const observer = new ResizeObserver((entries) => entries.forEach((e) => fit(e.target as HTMLElement)));
    tiles.forEach((t) => observer.observe(t));
    return () => {
      observer.disconnect();
      grid.style.gridAutoRows = "";
      tiles.forEach((t) => (t.style.gridRowEnd = ""));
    };
  }, [deps]);
  return ref;
}

type Layout = { order: string[]; sizes: TileSizes };

const key = (id: string) => id.toUpperCase();
const sizeOf = (sizes: TileSizes, id: string): TileSize => sizes[key(id)] ?? "small";

/** `posts` in the layout's order; anything it doesn't list (a new post) keeps its place after them. */
function arrange(posts: Post[], order: string[]): Post[] {
  const index = new Map(order.map((id, i) => [key(id), i]));
  const listed = posts.filter((p) => index.has(key(p.id))).sort((a, b) => index.get(key(a.id))! - index.get(key(b.id))!);
  return [...listed, ...posts.filter((p) => !index.has(key(p.id)))];
}

/**
 * A portfolio's Work grid. `posts` arrive already in the person's saved order and
 * `sizes` are their saved tile sizes. On your own portfolio (`editable`) an Edit grid
 * button lets you drag posts into a new order and make each one bigger or smaller;
 * Save writes it through savePortfolioLayout, so the app shows the same order.
 *
 * With every post small, the grid is the same masonry as the rest of the site. Once
 * any post is bigger it becomes a six-column grid read across in order, where a tall
 * post (a poster) spans several rows and the next posts fill in beside it.
 */
export default function PortfolioGrid({ posts, sizes, editable = false }: { posts: Post[]; sizes: TileSizes; editable?: boolean }) {
  const router = useRouter();
  const [layout, setLayout] = useState<Layout>(() => ({ order: posts.map((p) => p.id), sizes }));
  const [draft, setDraft] = useState<Layout | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [saving, startSaving] = useTransition();
  // The tile last swapped with and when, so a tile that slides under the pointer isn't swapped straight back.
  const lastSwap = useRef({ id: "", at: 0 });

  const shown = arrange(posts, layout.order);
  const custom = shown.some((p) => sizeOf(layout.sizes, p.id) !== "small");
  const editing = draft ? arrange(posts, draft.order) : [];
  // What each grid holds, so its tiles are re-measured whenever that changes.
  const tilesKey = (list: Post[], sizes: TileSizes) => list.map((p) => `${p.id}:${sizeOf(sizes, p.id)}`).join(",");
  const viewGrid = useRowSpans<HTMLDivElement>(draft || !custom ? "" : tilesKey(shown, layout.sizes));
  const editGrid = useRowSpans<HTMLUListElement>(draft ? tilesKey(editing, draft.sizes) : "");

  if (!draft) {
    return (
      <>
        {editable && (
          <div className="mb-4 flex flex-wrap items-center justify-end gap-3">
            {message && <p role="status" className={`text-sm ${message.error ? "text-red-500" : "text-muted"}`}>{message.text}</p>}
            <button
              type="button"
              onClick={() => {
                setMessage(null);
                setDraft({ order: shown.map((p) => p.id), sizes: { ...layout.sizes } });
              }}
              className="rounded-full border border-border px-4 py-1.5 text-sm font-medium transition hover:bg-surface"
            >
              Edit grid
            </button>
          </div>
        )}
        {custom ? (
          <div ref={viewGrid} className={GRID}>
            {shown.map((p, i) => (
              <div key={p.id} className={`min-w-0 ${TILE_GAP} ${SPAN[sizeOf(layout.sizes, p.id)]}`}>
                <ContentCard post={p} priority={i < 6} />
              </div>
            ))}
          </div>
        ) : (
          <PagedGrid posts={shown} />
        )}
      </>
    );
  }

  /** Moves a post to another place in the order. */
  function move(id: string, to: number) {
    setDraft((d) => {
      if (!d) return d;
      const order = arrange(posts, d.order).map((p) => p.id);
      const from = order.indexOf(id);
      if (from < 0 || to < 0 || to >= order.length || from === to) return d;
      order.splice(from, 1);
      order.splice(to, 0, id);
      return { ...d, order };
    });
  }

  function resize(id: string, step: -1 | 1) {
    setDraft((d) => {
      if (!d) return d;
      const next = TILE_SIZES[TILE_SIZES.indexOf(sizeOf(d.sizes, id)) + step];
      return next ? { ...d, sizes: { ...d.sizes, [key(id)]: next } } : d;
    });
  }

  function save() {
    const next = { order: editing.map((p) => p.id), sizes: draft!.sizes };
    startSaving(async () => {
      const result = await savePortfolioLayout(next.order, next.sizes).catch(() => ({ ok: false as const, message: "Couldn't save your layout. Try again in a moment." }));
      if (!result.ok) {
        setMessage({ text: result.message, error: true });
        return;
      }
      // If sizes couldn't be saved, keep showing the saved ones so the page matches what visitors see.
      setLayout(result.warning ? { order: next.order, sizes: layout.sizes } : next);
      setMessage(result.warning ? { text: result.warning, error: true } : { text: "Grid saved.", error: false });
      setDraft(null);
      router.refresh();
    });
  }

  return (
    <div>
      <div className="sticky top-0 z-10 -mx-3 mb-4 flex flex-wrap items-center gap-3 border-b border-border bg-background/95 px-3 py-3 backdrop-blur">
        <p className="mr-auto text-sm text-muted">
          Drag a post to move it, or use the arrows. Use <span aria-hidden>−</span> and <span aria-hidden>+</span> to make it smaller or bigger.
        </p>
        {message?.error && <p role="alert" className="w-full text-sm text-red-500 sm:w-auto">{message.text}</p>}
        <button
          type="button"
          disabled={saving}
          onClick={() => {
            setMessage(null);
            setDraft(null);
          }}
          className="rounded-full border border-border px-4 py-1.5 text-sm font-medium transition hover:bg-surface disabled:opacity-60"
        >
          Cancel
        </button>
        <button
          type="button"
          disabled={saving}
          onClick={save}
          className="rounded-full bg-brand px-5 py-1.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
        >
          {saving ? "Saving…" : "Save"}
        </button>
      </div>

      <ul ref={editGrid} className={GRID}>
        {editing.map((p, i) => {
          const size = sizeOf(draft.sizes, p.id);
          const thumb = thumbSources(p);
          return (
            <li
              key={p.id}
              draggable={!saving}
              onDragStart={(e) => {
                e.dataTransfer.effectAllowed = "move";
                e.dataTransfer.setData("text/plain", p.id);
                setDragging(p.id);
              }}
              onDragEnd={() => setDragging(null)}
              onDragOver={(e) => {
                if (dragging) e.preventDefault();
              }}
              onDragEnter={() => {
                if (!dragging || dragging === p.id) return;
                const now = Date.now();
                if (lastSwap.current.id === p.id && now - lastSwap.current.at < 300) return;
                lastSwap.current = { id: p.id, at: now };
                move(dragging, i);
              }}
              onDrop={(e) => e.preventDefault()}
              className={`min-w-0 cursor-grab select-none active:cursor-grabbing ${TILE_GAP} ${SPAN[size]} ${dragging === p.id ? "opacity-40" : ""}`}
            >
              <div
                className={`relative overflow-hidden rounded-xl ring-1 ring-border ${thumb.src ? "bg-black" : `bg-gradient-to-br ${TINT[p.category]}`}`}
                style={{ aspectRatio: p.aspect }}
              >
                {thumb.src && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={thumb.src} srcSet={thumb.srcSet} sizes="(min-width: 1024px) 40vw, 90vw" alt="" draggable={false} className="pointer-events-none h-full w-full object-cover" />
                )}
                <div className="absolute inset-x-0 bottom-0 flex items-center justify-between gap-2 bg-gradient-to-t from-black/80 to-transparent p-2 pt-8 text-white">
                  <div className="flex items-center gap-1">
                    <TileButton label={`Move ${p.title} earlier`} disabled={saving || i === 0} onClick={() => move(p.id, i - 1)}>
                      <path d="m15 6-6 6 6 6" />
                    </TileButton>
                    <TileButton label={`Move ${p.title} later`} disabled={saving || i === editing.length - 1} onClick={() => move(p.id, i + 1)}>
                      <path d="m9 6 6 6-6 6" />
                    </TileButton>
                  </div>
                  <div className="flex items-center gap-1">
                    <TileButton label={`Make ${p.title} smaller`} disabled={saving || size === TILE_SIZES[0]} onClick={() => resize(p.id, -1)}>
                      <path d="M6 12h12" />
                    </TileButton>
                    <span className="w-14 text-center text-xs font-semibold">{SIZE_LABEL[size]}</span>
                    <TileButton label={`Make ${p.title} bigger`} disabled={saving || size === TILE_SIZES[TILE_SIZES.length - 1]} onClick={() => resize(p.id, 1)}>
                      <path d="M6 12h12M12 6v12" />
                    </TileButton>
                  </div>
                </div>
              </div>
              <p className="mt-2 line-clamp-1 text-[15px] font-semibold leading-snug">{p.title}</p>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function TileButton({ label, disabled, onClick, children }: { label: string; disabled: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="flex h-8 w-8 items-center justify-center rounded-full bg-black/55 transition hover:bg-black/80 disabled:opacity-35"
    >
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4" aria-hidden>
        {children}
      </svg>
    </button>
  );
}
