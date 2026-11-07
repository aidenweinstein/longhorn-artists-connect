"use client";

import { useCallback, useEffect, useRef, useState, type CSSProperties, type PointerEvent, type ReactNode } from "react";
import { Audio, Video } from "./Media";
import { timecode } from "./Timecode";

const HOVER_DELAY_MS = 1000;
/** Length of the simulated preview's bar, for posts with no video or song yet. */
const PREVIEW_SECONDS = 15;
const PREVIEW_EVENT = "nexus:preview-start";

/**
 * Starts a preview, with sound, after the pointer rests on the card for one second,
 * and plays until the pointer leaves. Plays `videoUrl` when the post has one, or the
 * song at `audioUrl` over the slowly zooming cover; otherwise a simulated preview.
 * While playing, the bar and corner timecode follow the real playback.
 */
export default function HoverPreview({
  videoUrl,
  audioUrl,
  thumbnailUrl,
  aspect,
  playable,
  className,
  style,
  children,
}: {
  videoUrl?: string;
  audioUrl?: string;
  thumbnailUrl?: string;
  /** The server's best guess at the media's shape. */
  aspect: number;
  playable: boolean;
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const [playing, setPlaying] = useState(false);
  // Only true while the browser is holding back sound until the first click or key.
  const [muted, setMuted] = useState(false);
  // Real playback position, for the progress bar and the time left.
  const [clock, setClock] = useState({ time: 0, length: 0 });
  const track = (el: HTMLMediaElement) =>
    setClock({ time: el.currentTime, length: Number.isFinite(el.duration) ? el.duration : 0 });
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  // The thumbnail's real shape replaces the guess once it loads, so the card always
  // fits the picture exactly and never shows bars above or beside it.
  const [ratio, setRatio] = useState(aspect);
  const img = useRef<HTMLImageElement>(null);
  const measure = useCallback(() => {
    const el = img.current;
    if (el?.naturalWidth && el.naturalHeight) setRatio(el.naturalWidth / el.naturalHeight);
  }, []);
  // A cached image can finish loading before React attaches onLoad.
  useEffect(() => {
    if (img.current?.complete) measure();
  }, [measure]);

  // Also runs when Next.js hides this page in the background, so a preview never keeps playing off-screen.
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
    setPlaying(false);
  }, []);

  const box = useRef<HTMLDivElement>(null);
  const isHovered = () => !!box.current?.matches(":hover");

  // Only one preview plays at a time.
  useEffect(() => {
    const onOther = (e: Event) => {
      if ((e as CustomEvent).detail !== box.current) stop();
    };
    window.addEventListener(PREVIEW_EVENT, onOther);
    return () => window.removeEventListener(PREVIEW_EVENT, onOther);
  }, []);

  // While previewing, stop as soon as the pointer is no longer really over the card:
  // after scrolling it away, switching tabs or windows, or the card moving.
  useEffect(() => {
    if (!playing) return;
    const check = () => {
      if (document.hidden || !isHovered()) stop();
    };
    const interval = setInterval(check, 500);
    window.addEventListener("scroll", check, true);
    window.addEventListener("blur", stop);
    document.addEventListener("visibilitychange", check);
    return () => {
      clearInterval(interval);
      window.removeEventListener("scroll", check, true);
      window.removeEventListener("blur", stop);
      document.removeEventListener("visibilitychange", check);
    };
  }, [playing]);

  // Armed by real mouse movement over the card, not by the card sliding under a
  // still pointer (page load, scrolling, filtering), so nothing starts on its own.
  function arm(e: PointerEvent<HTMLDivElement>) {
    if (!playable || playing || timer.current || e.pointerType !== "mouse") return;
    timer.current = setTimeout(() => {
      timer.current = null;
      if (!isHovered() || document.hidden) return;
      window.dispatchEvent(new CustomEvent(PREVIEW_EVENT, { detail: box.current }));
      setPlaying(true);
    }, HOVER_DELAY_MS);
  }

  function stop() {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    setPlaying(false);
    setMuted(false);
    setClock({ time: 0, length: 0 });
  }

  return (
    <div ref={box} onPointerMove={arm} onPointerLeave={stop} className={className} style={{ ...style, aspectRatio: ratio }}>
      <div className={`absolute inset-0 flex items-center justify-center ${playing && !videoUrl ? "preview-zoom" : ""}`}>
        {children}
        {thumbnailUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img ref={img} src={thumbnailUrl} alt="" loading="lazy" onLoad={measure} className="absolute inset-0 h-full w-full object-cover" />
        )}
      </div>

      {playing && !videoUrl && audioUrl && (
        <Audio
          src={audioUrl}
          autoStart
          loop
          onVolumeChange={(e) => setMuted(e.currentTarget.muted)}
          onTimeUpdate={(e) => track(e.currentTarget)}
          onLoadedMetadata={(e) => track(e.currentTarget)}
        />
      )}

      {playing && videoUrl && (
        <Video
          src={videoUrl}
          autoStart
          loop
          playsInline
          onVolumeChange={(e) => setMuted(e.currentTarget.muted)}
          onTimeUpdate={(e) => track(e.currentTarget)}
          onLoadedMetadata={(e) => track(e.currentTarget)}
          className="absolute inset-0 h-full w-full object-contain"
        />
      )}

      {playing && (
        <>
          {(videoUrl || audioUrl) && muted && (
          <span className="absolute right-2 top-2 flex items-center gap-1 rounded-md bg-black/60 px-2 py-1 text-xs font-medium text-white">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6" />
            </svg>
            Muted
          </span>
          )}
          {clock.length > 0 && (
            // Covers the card's length badge with the time left while it plays.
            <span className="absolute bottom-2 right-2 z-10 rounded-md bg-black/75 px-1.5 py-0.5 font-mono text-xs font-semibold text-white">
              -{timecode(Math.max(0, clock.length - clock.time))}
            </span>
          )}
          <span className="absolute inset-x-0 bottom-0 z-10 h-1 bg-white/20">
            {clock.length > 0 ? (
              <span className="block h-full bg-brand" style={{ width: `${(clock.time / clock.length) * 100}%` }} />
            ) : (
              !videoUrl && !audioUrl && (
                <span className="block h-full bg-brand preview-progress" style={{ animationDuration: `${PREVIEW_SECONDS}s` }} />
              )
            )}
          </span>
        </>
      )}
    </div>
  );
}
