"use client";

import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { justGotSound, playWithSound } from "@/lib/autoplay";
import { takePrimed } from "@/lib/primedPlayback";

type MediaEl = HTMLVideoElement & {
  webkitShowPlaybackTargetPicker?: () => void;
  webkitEnterFullscreen?: () => void;
  remote?: { prompt: () => Promise<void> };
};

const HIDE_AFTER_MS = 2500;

/** The video the opening click already started for this post, or a fresh one. */
function mediaElement(postID: string | undefined): MediaEl {
  const adopted = postID ? takePrimed(postID) : null;
  return (adopted ?? document.createElement("video")) as MediaEl;
}

/** 75 → "1:15", 3725 → "1:02:05". */
function clock(seconds: number) {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const t = Math.floor(seconds);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = String(t % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

/**
 * YouTube-style player for a post's video or song. Controls appear while the pointer
 * is over the player (and hide again after a moment of stillness while playing):
 * play/pause, volume and time on the left; AirPlay/casting and fullscreen on the right.
 *
 * Keeps the media's true aspect ratio in both modes. Starts on open with sound (if the
 * browser refuses, sound comes on at the first click or key) and pauses whenever its page is hidden or left.
 */
export default function Player({
  src,
  poster,
  aspect,
  audioOnly = false,
  autoStart = false,
  postID,
  trackKey,
  onEnded,
  onPrev,
  onNext,
}: {
  /** Changes when a different song or video should load (e.g. the next track). A new download link for the same file keeps playing. */
  trackKey?: string | number;
  onEnded?: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  /** Set on a post's main player, so it can adopt the video started by the click that opened it. */
  postID?: string;
  src: string;
  poster?: string;
  aspect: number;
  audioOnly?: boolean;
  autoStart?: boolean;
}) {
  const frame = useRef<HTMLDivElement>(null);
  const media = useRef<MediaEl>(null);
  const slot = useRef<HTMLDivElement>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Only the visitor's own mute keeps a video or song silent; the browser's never does.
  const userMuted = useRef(false);

  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [full, setFull] = useState(false);
  const [hovering, setHovering] = useState(false);
  const [castable, setCastable] = useState(false);
  const [scrubbing, setScrubbing] = useState(false);
  // The thumbnail's shape is a first guess; the video's own dimensions win once known.
  const [ratio, setRatio] = useState(aspect);

  // Latest handlers for the element's listeners, which are attached once.
  const handlers = useRef({ toggle: () => {}, toggleFullscreen: () => {}, ended: () => {} });
  // CloudKit hands out a fresh signed link for the same file every few minutes, so the
  // link alone can't decide when to restart. Read the latest via refs; only trackKey restarts.
  const srcRef = useRef(src);
  const posterRef = useRef(poster);
  const pendingSrc = useRef<string | null>(null);

  /** Loads the waiting fresh link without losing the listener's place in the song. */
  function applyPendingSrc(el: HTMLMediaElement, resume = false) {
    const next = pendingSrc.current;
    if (!next) return;
    pendingSrc.current = null;
    const at = el.currentTime;
    const keepPlaying = resume || !el.paused;
    el.src = next;
    el.addEventListener(
      "loadedmetadata",
      () => {
        el.currentTime = at;
        if (keepPlaying) el.play().catch(() => {});
      },
      { once: true },
    );
  }

  // The <video> is created here rather than in JSX so it can be the element the
  // opening click already started (see primedPlayback.ts), which Safari lets play
  // with sound. Autostarts, and pauses when the page goes into the background.
  useEffect(() => {
    const host = slot.current;
    if (!host) return;
    const el = mediaElement(postID);
    if (el.getAttribute("src") !== srcRef.current) el.src = srcRef.current;
    if (!audioOnly && posterRef.current) el.poster = posterRef.current;
    pendingSrc.current = null;
    el.playsInline = true;
    el.preload = "metadata";
    el.setAttribute("x-webkit-airplay", "allow");
    el.className = `absolute inset-0 h-full w-full object-contain ${audioOnly ? "opacity-0" : ""}`;
    host.appendChild(el);
    media.current = el;

    const sync = () => {
      setPlaying(!el.paused);
      setTime(el.currentTime);
      if (Number.isFinite(el.duration)) setDuration(el.duration);
      setVolume(el.volume);
      setMuted(el.muted);
      if (!audioOnly && el.videoWidth && el.videoHeight) setRatio(el.videoWidth / el.videoHeight);
    };
    const listeners: [string, () => void][] = [
      ["click", () => handlers.current.toggle()],
      ["dblclick", () => handlers.current.toggleFullscreen()],
      ["play", () => setPlaying(true)],
      ["pause", () => {
        setPlaying(false);
        applyPendingSrc(el);
      }],
      // An expired link fails mid-song: pick up from the same spot with the fresh one.
      ["error", () => applyPendingSrc(el, true)],
      ["ended", () => handlers.current.ended()],
      ["timeupdate", () => setTime(el.currentTime)],
      ["durationchange", () => setDuration(el.duration)],
      ["loadedmetadata", sync],
      ["progress", () => {
        const b = el.buffered;
        if (b.length) setBuffered(b.end(b.length - 1));
      }],
      ["volumechange", () => {
        setVolume(el.volume);
        setMuted(el.muted);
      }],
    ];
    for (const [type, fn] of listeners) el.addEventListener(type, fn);
    // An adopted element may already have metadata loaded.
    if (el.readyState >= 1) sync();

    const stopWaiting = autoStart ? playWithSound(el) : undefined;
    return () => {
      stopWaiting?.();
      for (const [type, fn] of listeners) el.removeEventListener(type, fn);
      el.pause();
      el.remove();
      media.current = null;
    };
    // src and poster are read through refs on purpose; see srcRef above.
  }, [postID, trackKey, audioOnly, autoStart]);

  // A new link for the same file: swap it in while paused, otherwise keep playing the
  // current one and switch at the next pause (or if the old link stops working).
  useEffect(() => {
    srcRef.current = src;
    const el = media.current;
    if (!el || el.getAttribute("src") === src) return;
    pendingSrc.current = src;
    if (el.paused) applyPendingSrc(el);
  }, [src]);

  useEffect(() => {
    posterRef.current = poster;
    const el = media.current;
    if (el && !audioOnly && poster) el.poster = poster;
  }, [poster, audioOnly]);

  useEffect(() => {
    const onChange = () => setFull(document.fullscreenElement === frame.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  // AirPlay (Safari) or Cast / Remote Playback (Chrome, Edge).
  useEffect(() => {
    const el = media.current;
    if (!el) return;
    if ("WebKitPlaybackTargetAvailabilityEvent" in window) {
      const onAvail = (e: Event) => setCastable((e as Event & { availability: string }).availability === "available");
      el.addEventListener("webkitplaybacktargetavailabilitychanged", onAvail);
      return () => el.removeEventListener("webkitplaybacktargetavailabilitychanged", onAvail);
    }
    if (el.remote) setCastable(true);
  }, []);

  const showControls = useCallback(() => {
    setHovering(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setHovering(false), HIDE_AFTER_MS);
  }, []);

  useEffect(() => () => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
  }, []);

  const visible = hovering || scrubbing || (!playing && hovering);

  function toggle() {
    const el = media.current;
    if (!el) return;
    // Clicking a video or song that the browser started silently turns its sound on
    // and keeps it playing, instead of pausing it.
    if (justGotSound(el)) {
      if (el.paused) el.play().catch(() => {});
      return;
    }
    if (el.muted && !el.paused && !userMuted.current) {
      el.muted = false;
      return;
    }
    if (el.paused) {
      // Starting playback always comes with sound unless the visitor muted it themselves.
      if (!userMuted.current) el.muted = false;
      el.play().catch(() => {});
    }
    else el.pause();
  }

  function seekTo(seconds: number) {
    const el = media.current;
    if (!el || !duration) return;
    el.currentTime = Math.max(0, Math.min(duration, seconds));
  }

  function toggleMute() {
    const el = media.current;
    if (!el) return;
    el.muted = !el.muted;
    userMuted.current = el.muted;
    if (!el.muted && el.volume === 0) el.volume = 0.5;
  }

  function setVol(v: number) {
    const el = media.current;
    if (!el) return;
    el.volume = v;
    el.muted = v === 0;
    userMuted.current = v === 0;
  }

  function toggleFullscreen() {
    const el = media.current;
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else if (frame.current?.requestFullscreen) {
      frame.current.requestFullscreen().catch(() => el?.webkitEnterFullscreen?.());
    } else {
      el?.webkitEnterFullscreen?.();
    }
  }

  useEffect(() => {
    handlers.current = { toggle, toggleFullscreen, ended: () => onEnded?.() };
  });

  function cast() {
    const el = media.current;
    if (!el) return;
    if (el.webkitShowPlaybackTargetPicker) el.webkitShowPlaybackTargetPicker();
    else el.remote?.prompt().catch(() => {});
  }

  function scrubFromPointer(e: PointerEvent<HTMLDivElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    seekTo(((e.clientX - rect.left) / rect.width) * duration);
  }

  function onKey(e: KeyboardEvent) {
    const key = e.key.toLowerCase();
    if (key === " " || key === "k") toggle();
    else if (key === "f") toggleFullscreen();
    else if (key === "m") toggleMute();
    else if (key === "arrowright" || key === "l") seekTo(time + (key === "l" ? 10 : 5));
    else if (key === "arrowleft" || key === "j") seekTo(time - (key === "j" ? 10 : 5));
    else if (key === "arrowup") setVol(Math.min(1, volume + 0.1));
    else if (key === "arrowdown") setVol(Math.max(0, volume - 0.1));
    else return;
    e.preventDefault();
    showControls();
  }

  const progress = duration ? (time / duration) * 100 : 0;
  const loaded = duration ? (buffered / duration) * 100 : 0;
  const level = muted ? 0 : volume;

  return (
    <div
      ref={frame}
      tabIndex={0}
      onKeyDown={onKey}
      onPointerMove={showControls}
      onPointerEnter={showControls}
      onPointerLeave={() => !scrubbing && setHovering(false)}
      // Sized to the media itself so there are never bars beside or above it.
      style={full ? undefined : { width: `min(100%, calc((100vh - 9rem) * ${ratio}))` }}
      className={`group/player relative flex items-center justify-center outline-none ${
        full ? "h-screen w-screen bg-black" : "mx-auto overflow-hidden rounded-2xl"
      } ${visible ? "" : "cursor-none"}`}
    >
      <div
        className="relative"
        style={{ aspectRatio: ratio, width: full ? `min(100%, calc(100vh * ${ratio}))` : "100%" }}
      >
        {audioOnly && poster && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={poster} alt="" className="absolute inset-0 h-full w-full object-contain" />
        )}
        <div ref={slot} className="absolute inset-0" />
      </div>

      {/* Bottom gradient + controls, YouTube-style */}
      <div
        className={`pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-black/75 to-transparent transition-opacity duration-200 ${
          visible ? "opacity-100" : "opacity-0"
        }`}
      />
      <div
        className={`absolute inset-x-0 bottom-0 px-3 pb-2 text-white transition-opacity duration-200 ${
          visible ? "opacity-100" : "pointer-events-none opacity-0"
        }`}
      >
        {/* Progress / scrub bar */}
        <div
          role="slider"
          aria-label="Seek"
          aria-valuemin={0}
          aria-valuemax={Math.round(duration)}
          aria-valuenow={Math.round(time)}
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId);
            setScrubbing(true);
            scrubFromPointer(e);
          }}
          onPointerMove={(e) => scrubbing && scrubFromPointer(e)}
          onPointerUp={() => setScrubbing(false)}
          className="group/seek relative flex h-4 cursor-pointer items-center"
        >
          <div className="relative h-1 w-full rounded-full bg-white/25 transition-[height] group-hover/seek:h-1.5">
            <div className="absolute inset-y-0 left-0 rounded-full bg-white/40" style={{ width: `${loaded}%` }} />
            <div className="absolute inset-y-0 left-0 rounded-full bg-brand" style={{ width: `${progress}%` }} />
            <div
              className="absolute top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 scale-0 rounded-full bg-brand transition-transform group-hover/seek:scale-100"
              style={{ left: `${progress}%` }}
            />
          </div>
        </div>

        <div className="flex items-center gap-1">
          {onPrev && (
            <IconButton label="Previous track" onClick={onPrev}>
              <path d="M6 5v14M19 5v14L8.5 12z" fill="currentColor" />
            </IconButton>
          )}
          <IconButton label={playing ? "Pause (k)" : "Play (k)"} onClick={toggle}>
            {playing ? (
              <path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor" stroke="none" />
            ) : (
              <path d="M7 4.5v15l12-7.5z" fill="currentColor" stroke="none" />
            )}
          </IconButton>

          {onNext && (
            <IconButton label="Next track" onClick={onNext}>
              <path d="M18 5v14M5 5v14l10.5-7z" fill="currentColor" />
            </IconButton>
          )}

          <div className="group/vol flex items-center">
            <IconButton label={level === 0 ? "Unmute (m)" : "Mute (m)"} onClick={toggleMute}>
              <path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor" stroke="none" />
              {level === 0 ? (
                <path d="m16 9.5 5 5M21 9.5l-5 5" />
              ) : (
                <>
                  <path d="M15.5 9a4.2 4.2 0 0 1 0 6" />
                  {level > 0.5 && <path d="M18 6.5a7.8 7.8 0 0 1 0 11" />}
                </>
              )}
            </IconButton>
            <input
              type="range"
              min={0}
              max={1}
              step={0.01}
              value={level}
              onChange={(e) => setVol(Number(e.target.value))}
              aria-label="Volume"
              className="w-0 cursor-pointer accent-white opacity-0 transition-all duration-200 group-hover/vol:mr-2 group-hover/vol:w-20 group-hover/vol:opacity-100 focus:mr-2 focus:w-20 focus:opacity-100"
            />
          </div>

          <span className="ml-1 font-mono text-[13px] tabular-nums">
            {clock(time)} <span className="text-white/60">/ {clock(duration)}</span>
          </span>

          <div className="ml-auto flex items-center gap-1">
            {castable && (
              <IconButton label="AirPlay / Cast" onClick={cast}>
                <path d="M6 17H4.5A1.5 1.5 0 0 1 3 15.5v-9A1.5 1.5 0 0 1 4.5 5h15A1.5 1.5 0 0 1 21 6.5v9a1.5 1.5 0 0 1-1.5 1.5H18" />
                <path d="m12 14 5 6H7z" fill="currentColor" stroke="none" />
              </IconButton>
            )}
            {!audioOnly && (
              <IconButton label={full ? "Exit fullscreen (f)" : "Fullscreen (f)"} onClick={toggleFullscreen}>
                {full ? (
                  <path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" />
                ) : (
                  <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
                )}
              </IconButton>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function IconButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="flex h-10 w-10 items-center justify-center rounded-full transition hover:bg-white/15"
    >
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        {children}
      </svg>
    </button>
  );
}
