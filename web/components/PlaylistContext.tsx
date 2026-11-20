"use client";

import { createContext, useContext, useMemo, useState, type ReactNode } from "react";

type PlaylistState = {
  /** The video playing (or about to), by its place in the playlist. */
  index: number;
  /** Whether playback has begun: a video picked from the list or the cast always plays. */
  started: boolean;
  /** Switches to a video and plays it. */
  go: (index: number) => void;
};

const Ctx = createContext<PlaylistState | null>(null);

/**
 * Shares which showcase video is playing between the player (VideoPlaylist) and the
 * post's Cast list (ShowcaseCast), so the cast can highlight who's on screen and switch
 * the player to someone else's video.
 */
export function PlaylistProvider({ count, autoStart = false, children }: { count: number; autoStart?: boolean; children: ReactNode }) {
  const [index, setIndex] = useState(0);
  const [started, setStarted] = useState(autoStart);
  const value = useMemo<PlaylistState>(
    () => ({
      index: Math.min(index, Math.max(0, count - 1)),
      started,
      go: (i) => {
        setStarted(true);
        setIndex(Math.max(0, Math.min(count - 1, i)));
      },
    }),
    [index, started, count],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

/** The shared playlist state, or null outside a PlaylistProvider. */
export const usePlaylist = () => useContext(Ctx);
