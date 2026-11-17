"use client";

import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";
import { createPortal } from "react-dom";
import { normalizeCrop, type VideoCrop } from "@/lib/videoCrop";

/** Shapes to lock the box to, as width ÷ height. "Original" is the video's own shape. */
const ASPECTS: { label: string; ratio: number | "original" | null }[] = [
  { label: "Free", ratio: null },
  { label: "Original", ratio: "original" },
  { label: "16:9", ratio: 16 / 9 },
  { label: "2.39:1", ratio: 2.39 },
  { label: "4:3", ratio: 4 / 3 },
  { label: "3:2", ratio: 3 / 2 },
  { label: "1:1", ratio: 1 },
  { label: "4:5", ratio: 4 / 5 },
  { label: "9:16", ratio: 9 / 16 },
];

const FULL: VideoCrop = { x: 0, y: 0, w: 1, h: 1 };
const MIN = 0.05;
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

type Corner = "tl" | "tr" | "bl" | "br";
type Drag =
  | { kind: "move"; startX: number; startY: number; from: VideoCrop }
  | { kind: "corner"; corner: Corner; anchorX: number; anchorY: number };

/**
 * The web version of the app's crop editor for videos. Nothing is re-encoded: it hands
 * back a playback crop (a rect of the frame) that the player zooms to, so the film keeps
 * its full original quality. Drag the box to move it, drag a corner to resize, and
 * scrub to check the framing anywhere in the video.
 */
export default function VideoCropEditor({
  file,
  initial,
  onCancel,
  onDone,
}: {
  file: File;
  initial: VideoCrop | null;
  onCancel: () => void;
  /** `null` when the whole frame is kept. */
  onDone: (crop: VideoCrop | null) => void;
}) {
  // Made in an effect (not useMemo) so React's development double-mount, which runs the
  // cleanup once straight away, can't revoke the link before the video has loaded it.
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    const u = URL.createObjectURL(file);
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setUrl(u);
    setFailed(false);
    return () => URL.revokeObjectURL(u);
  }, [file]);

  const stage = useRef<HTMLDivElement>(null);
  const video = useRef<HTMLVideoElement>(null);
  const drag = useRef<Drag | null>(null);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [rect, setRect] = useState<VideoCrop>(initial ?? FULL);
  const [aspect, setAspect] = useState<string>("Free");
  const [time, setTime] = useState(0);
  const [length, setLength] = useState(0);

  // Escape cancels; the page behind doesn't scroll while the editor is open.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onCancel();
    window.addEventListener("keydown", onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
    };
  }, [onCancel]);

  /** The locked shape in 0…1 units of the frame (where the whole frame is 1×1), or null when free. */
  const lockedRatio = (label = aspect): number | null => {
    const option = ASPECTS.find((a) => a.label === label);
    if (!option?.ratio || !natural) return null;
    if (option.ratio === "original") return 1;
    return (option.ratio * natural.h) / natural.w;
  };

  function chooseAspect(label: string) {
    setAspect(label);
    const r = lockedRatio(label);
    if (!r) return;
    // The largest box of that shape, kept centered where the current box is.
    const w = r >= 1 ? 1 : r;
    const h = r >= 1 ? 1 / r : 1;
    const cx = rect.x + rect.w / 2;
    const cy = rect.y + rect.h / 2;
    setRect({ x: clamp(cx - w / 2, 0, 1 - w), y: clamp(cy - h / 2, 0, 1 - h), w, h });
  }

  /** The pointer's position in 0…1 units of the frame. */
  function point(e: ReactPointerEvent) {
    const box = stage.current!.getBoundingClientRect();
    return { x: clamp((e.clientX - box.left) / box.width, 0, 1), y: clamp((e.clientY - box.top) / box.height, 0, 1) };
  }

  function startMove(e: ReactPointerEvent) {
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    const p = point(e);
    drag.current = { kind: "move", startX: p.x, startY: p.y, from: rect };
  }

  function startCorner(corner: Corner, e: ReactPointerEvent) {
    e.preventDefault();
    e.stopPropagation();
    e.currentTarget.setPointerCapture(e.pointerId);
    // The opposite corner stays put.
    const anchorX = corner === "tl" || corner === "bl" ? rect.x + rect.w : rect.x;
    const anchorY = corner === "tl" || corner === "tr" ? rect.y + rect.h : rect.y;
    drag.current = { kind: "corner", corner, anchorX, anchorY };
  }

  function onMove(e: ReactPointerEvent) {
    const d = drag.current;
    if (!d) return;
    const p = point(e);
    if (d.kind === "move") {
      setRect({
        ...d.from,
        x: clamp(d.from.x + p.x - d.startX, 0, 1 - d.from.w),
        y: clamp(d.from.y + p.y - d.startY, 0, 1 - d.from.h),
      });
      return;
    }
    const right = d.corner === "tr" || d.corner === "br";
    const down = d.corner === "bl" || d.corner === "br";
    const maxW = right ? 1 - d.anchorX : d.anchorX;
    const maxH = down ? 1 - d.anchorY : d.anchorY;
    let w = clamp(Math.abs(p.x - d.anchorX), MIN, maxW);
    let h = clamp(Math.abs(p.y - d.anchorY), MIN, maxH);
    const r = lockedRatio();
    if (r) {
      w = Math.min(Math.max(w, h * r), maxW, maxH * r);
      h = w / r;
    }
    setRect({ x: right ? d.anchorX : d.anchorX - w, y: down ? d.anchorY : d.anchorY - h, w, h });
  }

  const endDrag = () => {
    drag.current = null;
  };

  // Arrow keys nudge the box; hold Shift for bigger steps.
  function onKey(e: ReactKeyboardEvent) {
    const step = e.shiftKey ? 0.05 : 0.01;
    const by = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[e.key];
    if (!by) return;
    e.preventDefault();
    setRect((r) => ({ ...r, x: clamp(r.x + by[0], 0, 1 - r.w), y: clamp(r.y + by[1], 0, 1 - r.h) }));
  }

  const ratio = natural ? natural.w / natural.h : 16 / 9;
  const pct = (n: number) => `${n * 100}%`;
  const outW = natural ? Math.round(rect.w * natural.w) : 0;
  const outH = natural ? Math.round(rect.h * natural.h) : 0;

  const editor = (
    <div role="dialog" aria-modal="true" aria-label="Crop video" className="fixed inset-0 z-[100] flex flex-col bg-black text-white">
      <div className="flex items-center justify-between px-4 py-3">
        <button type="button" onClick={onCancel} className="text-[15px] text-white/80 hover:text-white">
          Cancel
        </button>
        <h2 className="text-[15px] font-semibold">Crop</h2>
        <button type="button" onClick={() => onDone(normalizeCrop(rect))} className="text-[15px] font-semibold text-brand hover:underline">
          Done
        </button>
      </div>

      <div className="flex min-h-0 flex-1 items-center justify-center px-4">
        <div
          ref={stage}
          className="relative touch-none select-none"
          style={{ aspectRatio: ratio, width: `min(100%, calc((100vh - 15rem) * ${ratio}))` }}
          onPointerMove={onMove}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
        >
          {url && (
          <video
            ref={video}
            src={url}
            muted
            playsInline
            preload="auto"
            onLoadedMetadata={(e) => {
              const v = e.currentTarget;
              if (v.videoWidth && v.videoHeight) setNatural({ w: v.videoWidth, h: v.videoHeight });
              if (Number.isFinite(v.duration)) {
                setLength(v.duration);
                // The very first frame is often black; show one just after it.
                v.currentTime = Math.min(0.5, v.duration / 2);
              }
            }}
            onLoadedData={(e) => {
              // Some browsers only report the size once a frame has loaded.
              const v = e.currentTarget;
              if (v.videoWidth && v.videoHeight) setNatural((n) => n ?? { w: v.videoWidth, h: v.videoHeight });
            }}
            onError={() => setFailed(true)}
            onTimeUpdate={(e) => setTime(e.currentTarget.currentTime)}
            className="absolute inset-0 h-full w-full bg-neutral-900 object-fill"
          />
          )}
          {natural && (
            <div
              tabIndex={0}
              aria-label="Crop area. Drag to move, or use the arrow keys."
              onPointerDown={startMove}
              onKeyDown={onKey}
              className="absolute cursor-move outline-none ring-white focus-visible:ring-2"
              style={{
                left: pct(rect.x),
                top: pct(rect.y),
                width: pct(rect.w),
                height: pct(rect.h),
                // Dims everything outside the box.
                boxShadow: "0 0 0 9999px rgba(0,0,0,0.6)",
              }}
            >
              <div className="pointer-events-none absolute inset-0 border border-white/90" />
              {/* Rule of thirds. */}
              <div className="pointer-events-none absolute inset-y-0 left-1/3 w-px bg-white/30" />
              <div className="pointer-events-none absolute inset-y-0 left-2/3 w-px bg-white/30" />
              <div className="pointer-events-none absolute inset-x-0 top-1/3 h-px bg-white/30" />
              <div className="pointer-events-none absolute inset-x-0 top-2/3 h-px bg-white/30" />
              {(["tl", "tr", "bl", "br"] as Corner[]).map((c) => (
                <span
                  key={c}
                  onPointerDown={(e) => startCorner(c, e)}
                  className={`absolute h-6 w-6 ${c[0] === "t" ? "-top-1.5" : "-bottom-1.5"} ${c[1] === "l" ? "-left-1.5" : "-right-1.5"} ${
                    c === "tl" || c === "br" ? "cursor-nwse-resize" : "cursor-nesw-resize"
                  }`}
                >
                  <span
                    className={`absolute h-5 w-5 border-white ${c[0] === "t" ? "top-1.5 border-t-[3px]" : "bottom-1.5 border-b-[3px]"} ${
                      c[1] === "l" ? "left-1.5 border-l-[3px]" : "right-1.5 border-r-[3px]"
                    }`}
                  />
                </span>
              ))}
            </div>
          )}
          {!natural && (
            <p className="absolute inset-0 flex items-center justify-center px-6 text-center text-sm text-white/60">
              {failed ? "This browser can't play this video file, so it can't be cropped here. Try Chrome or Safari, or export it as an MP4 (H.264)." : "Loading video…"}
            </p>
          )}
        </div>
      </div>

      <div className="mx-auto w-full max-w-3xl space-y-3 px-4 pb-5 pt-4">
        <input
          type="range"
          min={0}
          max={length || 1}
          step={0.01}
          value={time}
          disabled={!length}
          aria-label="Scrub to check the framing"
          onChange={(e) => {
            const t = Number(e.target.value);
            setTime(t);
            if (video.current) video.current.currentTime = t;
          }}
          className="w-full accent-brand"
        />
        <div className="flex flex-wrap items-center justify-center gap-2">
          {ASPECTS.map((a) => (
            <button
              key={a.label}
              type="button"
              onClick={() => chooseAspect(a.label)}
              disabled={!natural}
              className={`rounded-full px-3 py-1 text-sm transition ${aspect === a.label ? "bg-white text-black" : "bg-white/15 hover:bg-white/25"}`}
            >
              {a.label}
            </button>
          ))}
          <button
            type="button"
            onClick={() => {
              setAspect("Free");
              setRect(FULL);
            }}
            className="rounded-full px-3 py-1 text-sm text-white/70 hover:text-white"
          >
            Reset
          </button>
        </div>
        <p className="text-center text-xs text-white/50">
          {natural ? `${outW} × ${outH} · ` : ""}The video isn&apos;t re-encoded; it keeps its full original quality and plays cropped.
        </p>
      </div>
    </div>
  );

  return typeof document === "undefined" ? null : createPortal(editor, document.body);
}
