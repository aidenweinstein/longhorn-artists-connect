"use client";

import { useEffect, useState } from "react";
import Player from "./Player";

/** 75 → "1:15". */
function clock(seconds?: number) {
  if (!seconds || !Number.isFinite(seconds)) return "";
  const t = Math.round(seconds);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
}

/**
 * An EP or album: the player plus a numbered tracklist. Songs play straight through,
 * and any track can be picked from the list or skipped to with the player's buttons.
 */
export default function MusicPlayer({
  tracks,
  poster,
  aspect,
  firstDuration,
  autoStart = false,
}: {
  tracks: string[];
  poster?: string;
  aspect: number;
  /** Track 1's saved length, so it shows before anything loads. */
  firstDuration?: number;
  autoStart?: boolean;
}) {
  const [index, setIndex] = useState(0);
  // Picking a track always plays it, even when the post didn't autostart.
  const [started, setStarted] = useState(autoStart);
  const [durations, setDurations] = useState<(number | undefined)[]>(() => [firstDuration]);

  // The app doesn't save each extra track's length, so read it from the file.
  // Only the track count matters here: fresh download links for the same files don't need re-reading.
  const count = tracks.length;
  useEffect(() => {
    const probes = tracks.map((src, i) => {
      const a = new Audio();
      a.preload = "metadata";
      a.onloadedmetadata = () =>
        setDurations((d) => {
          const next = [...d];
          next[i] = a.duration;
          return next;
        });
      a.src = src;
      return a;
    });
    return () => probes.forEach((a) => a.removeAttribute("src"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [count]);

  const go = (i: number) => {
    setStarted(true);
    setIndex(Math.max(0, Math.min(count - 1, i)));
  };

  return (
    <div>
      <Player
        src={tracks[index]}
        trackKey={index}
        poster={poster}
        aspect={aspect}
        audioOnly
        autoStart={started}
        onEnded={() => index < count - 1 && go(index + 1)}
        onPrev={index > 0 ? () => go(index - 1) : undefined}
        onNext={index < count - 1 ? () => go(index + 1) : undefined}
      />
      <ol className="mt-4 divide-y divide-border overflow-hidden rounded-2xl bg-surface">
        {tracks.map((src, i) => {
          const current = i === index;
          return (
            <li key={i}>
              <button
                type="button"
                onClick={() => go(i)}
                aria-current={current ? "true" : undefined}
                className={`flex w-full items-center gap-4 px-4 py-3 text-left text-sm transition-colors hover:bg-foreground/5 ${
                  current ? "font-semibold text-brand" : ""
                }`}
              >
                <span className="w-5 text-right tabular-nums text-muted">{i + 1}</span>
                <span className="flex-1">Track {i + 1}</span>
                <span className="tabular-nums text-muted">{clock(durations[i])}</span>
              </button>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
