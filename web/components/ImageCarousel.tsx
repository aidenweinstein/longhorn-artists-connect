"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import MediaViewer from "./MediaViewer";

/**
 * Swipe, scroll, arrow-key or tap the dots to move through a post's pictures. The frame takes the
 * shape of whichever picture is showing, so no picture ever gets bars around it.
 */
export default function ImageCarousel({ images, aspect }: { images: string[]; aspect: number }) {
  const track = useRef<HTMLDivElement>(null);
  const [index, setIndex] = useState(0);
  const [ratios, setRatios] = useState<Record<number, number>>({});
  const many = images.length > 1;

  // Keep the counter and dots in step with swipes and trackpad scrolls.
  useEffect(() => {
    const el = track.current;
    if (!el) return;
    const onScroll = () => {
      const i = Math.round(el.scrollLeft / el.clientWidth);
      setIndex(Math.max(0, Math.min(images.length - 1, i)));
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, [images.length]);

  // The frame reshapes for each picture; keep the current one lined up when it does.
  const shown = useRef(0);
  useEffect(() => {
    shown.current = index;
  }, [index]);
  useEffect(() => {
    const el = track.current;
    if (!el) return;
    const ro = new ResizeObserver(() => {
      el.scrollTo({ left: shown.current * el.clientWidth, behavior: "instant" });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  function go(i: number) {
    const el = track.current;
    if (!el) return;
    const next = (i + images.length) % images.length;
    el.scrollTo({ left: next * el.clientWidth, behavior: "smooth" });
    setIndex(next);
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === "ArrowRight") go(index + 1);
    else if (e.key === "ArrowLeft") go(index - 1);
    else return;
    e.preventDefault();
  }


  return (
    <MediaViewer aspect={ratios[index] ?? aspect}>
      <div tabIndex={many ? 0 : -1} onKeyDown={onKey} className="absolute inset-0 outline-none" aria-roledescription="carousel">
        <div
          ref={track}
          className="flex h-full w-full snap-x snap-mandatory overflow-x-auto overscroll-x-contain [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          {images.map((src, i) => (
            <div key={src} className="h-full w-full shrink-0 snap-center" aria-label={`Picture ${i + 1} of ${images.length}`}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={src}
                alt=""
                loading={i === 0 ? "eager" : "lazy"}
                draggable={false}
                onLoad={(e) => {
                  const { naturalWidth: w, naturalHeight: h } = e.currentTarget;
                  if (w && h) setRatios((r) => ({ ...r, [i]: w / h }));
                }}
                className="h-full w-full select-none object-contain"
              />
            </div>
          ))}
        </div>

        {many && (
          <>
            <span className="absolute right-3 top-3 rounded-full bg-black/55 px-2.5 py-1 text-xs font-semibold text-white backdrop-blur">
              {index + 1} / {images.length}
            </span>
            <div className="absolute inset-x-0 bottom-3 flex justify-center gap-1.5">
              {images.map((src, i) => (
                <button
                  key={src}
                  type="button"
                  onClick={() => go(i)}
                  aria-label={`Show picture ${i + 1}`}
                  aria-current={i === index}
                  className={`h-2 rounded-full transition-all ${i === index ? "w-5 bg-white" : "w-2 bg-white/50 hover:bg-white/80"}`}
                />
              ))}
            </div>
          </>
        )}
      </div>
    </MediaViewer>
  );
}
