"use client";

import Link from "next/link";
import { useState } from "react";
import type { PlaylistVideo } from "@/lib/mockContent";
import Player from "./Player";
import { usePlaylist } from "./PlaylistContext";

/**
 * A performance post with several videos (an actor showcase, say): the player plus a
 * numbered list. Videos play straight through, and any one can be picked from the list
 * or skipped to with the player's previous and next buttons.
 */
export default function VideoPlaylist({
  videos,
  postID,
  poster,
  aspect,
  crop,
  autoStart = false,
}: {
  /** The post's own first video's playback crop. */
  crop?: string;
  /** `postID` is set for a video that is an existing post added to the playlist. */
  videos: PlaylistVideo[];
  postID: string;
  poster?: string;
  aspect: number;
  autoStart?: boolean;
}) {
  // Inside a PlaylistProvider (the post page) the playing video is shared with the Cast list.
  const shared = usePlaylist();
  const [ownIndex, setIndex] = useState(0);
  // Picking a video always plays it, even when the post didn't autostart.
  const [ownStarted, setStarted] = useState(autoStart);
  const count = videos.length;
  const index = shared ? shared.index : ownIndex;
  const started = shared ? shared.started : ownStarted;
  const at = Math.min(index, count - 1);

  const go = (i: number) => {
    if (shared) return shared.go(i);
    setStarted(true);
    setIndex(Math.max(0, Math.min(count - 1, i)));
  };

  return (
    <div>
      <Player
        postID={postID}
        src={videos[at].url}
        trackKey={at}
        // Each video shows its own thumbnail; without one, the first falls back to the post's
        // main thumbnail and later ones to their own first frame.
        poster={videos[at].thumb ?? (at === 0 ? poster : undefined)}
        aspect={aspect}
        crop={at === 0 && !videos[0].postID ? crop : undefined}
        autoStart={started}
        onEnded={() => at < count - 1 && go(at + 1)}
        onPrev={at > 0 ? () => go(at - 1) : undefined}
        onNext={at < count - 1 ? () => go(at + 1) : undefined}
      />
      <ol className="mt-4 divide-y divide-border overflow-hidden rounded-2xl bg-surface">
        {videos.map((v, i) => {
          const current = i === at;
          return (
            <li key={i} className="flex items-center">
              <button
                type="button"
                onClick={() => go(i)}
                aria-current={current ? "true" : undefined}
                className={`flex min-w-0 flex-1 items-center gap-4 px-4 py-3 text-left text-sm transition-colors hover:bg-foreground/5 ${
                  current ? "font-semibold text-brand" : ""
                }`}
              >
                <span className="w-5 text-right tabular-nums text-muted">{i + 1}</span>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                {v.thumb ? <img src={v.thumb} alt="" loading="lazy" className="h-10 w-16 shrink-0 rounded-md bg-black object-cover" /> : null}
                <span className="min-w-0 flex-1">
                  <span className="block truncate">{v.title || `Video ${i + 1}`}</span>
                  {v.actor && <span className={`block truncate text-xs ${current ? "text-brand/80" : "text-muted"} font-normal`}>{v.actor.name}</span>}
                </span>
                {current && <span className="text-xs font-medium uppercase tracking-wide">Playing</span>}
              </button>
              {/* The video's own post: its credits, description and likes. */}
              {v.postID && (
                <Link href={`/post/${v.postID}`} className="shrink-0 px-4 py-3 text-xs font-medium text-muted hover:text-foreground">
                  Open post
                </Link>
              )}
            </li>
          );
        })}
      </ol>
    </div>
  );
}
