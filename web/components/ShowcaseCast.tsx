"use client";

import type { ReactNode } from "react";
import { usePlaylist } from "./PlaylistContext";

/** One video's performer, with the person (name, picture, profile link) drawn on the server. */
export type ShowcaseCastRow = { index: number; role: string; person: ReactNode };

/**
 * A showcase's Cast: who's in each video, in playing order. The person on screen now is
 * highlighted, and picking anyone switches the player to their video.
 */
export default function ShowcaseCast({ rows }: { rows: ShowcaseCastRow[] }) {
  const playlist = usePlaylist();
  const at = playlist?.index ?? 0;
  return (
    <div>
      <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Cast</h2>
      <ul className="mt-3 divide-y divide-border">
        {rows.map((row) => {
          const current = row.index === at;
          return (
            <li
              key={row.index}
              aria-current={current ? "true" : undefined}
              className={`-mx-2 flex items-center justify-between gap-4 rounded-lg px-2 py-2.5 transition-colors ${current ? "bg-brand/10" : ""}`}
            >
              <button
                type="button"
                onClick={() => playlist?.go(row.index)}
                title={current ? "Playing now" : "Play this video"}
                className={`flex min-w-0 flex-1 items-center gap-2.5 text-left text-sm ${current ? "font-semibold text-brand" : "text-muted hover:text-foreground"}`}
              >
                <span className="flex w-4 shrink-0 justify-center" aria-hidden>
                  {current ? <NowPlaying /> : <PlayIcon />}
                </span>
                <span className="truncate">{row.role}</span>
                {current && <span className="sr-only">(playing now)</span>}
              </button>
              <span className={current ? "text-brand" : ""}>{row.person}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 12 12" className="h-3 w-3">
      <path d="M3 1.8v8.4L10 6z" fill="currentColor" />
    </svg>
  );
}

/** Three bars, like a level meter, for the video playing now. */
function NowPlaying() {
  return (
    <span className="flex h-3 items-end gap-[2px]">
      {[0, 1, 2].map((i) => (
        <span key={i} className="w-[3px] animate-pulse rounded-sm bg-current" style={{ height: `${[60, 100, 40][i]}%`, animationDelay: `${i * 150}ms` }} />
      ))}
    </span>
  );
}
