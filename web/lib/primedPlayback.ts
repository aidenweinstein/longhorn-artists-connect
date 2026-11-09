/**
 * Safari only lets a video play with sound if it was started during a click. The
 * post page's player mounts after the click has finished, so on its own it would
 * start muted. Instead, clicking a post starts a video element right then (which
 * unlocks sound for that element), pauses it, and the post page's player adopts
 * that same element. Chrome and Firefox are fine either way.
 */

import { forgetOffPage, trackOffPage } from "./autoplay";

let primed: { postID: string; el: HTMLVideoElement; timer: ReturnType<typeof setTimeout> } | null = null;

/** If no player adopts the element soon (navigation cancelled, slow load), silence it for good. */
const GIVE_UP_MS = 8000;

function discard(el: HTMLVideoElement) {
  el.pause();
  el.removeAttribute("src");
  el.load();
  forgetOffPage(el);
}

/** Call synchronously from the click that opens a post. */
export function primePlayback(postID: string, src: string) {
  if (typeof document === "undefined") return;
  if (primed) clearTimeout(primed.timer);
  const el = primed?.el ?? document.createElement("video");
  trackOffPage(el);
  el.playsInline = true;
  el.preload = "auto";
  el.src = src;
  el.muted = false;
  const timer = setTimeout(() => {
    if (primed?.el === el) {
      primed = null;
      discard(el);
    }
  }, GIVE_UP_MS);
  primed = { postID, el, timer };
  el.play().then(
    () => {
      // Unlocked. Hold silently at the start until the player takes over, unless it already has.
      if (primed?.el === el) {
        el.pause();
        el.currentTime = 0;
      }
    },
    () => {},
  );
}

/**
 * The element primed for this post, if any. Each element is handed out once, and
 * one primed for a different post is silenced rather than left playing off-page.
 */
export function takePrimed(postID: string): HTMLVideoElement | null {
  if (!primed) return null;
  const { el, timer, postID: primedFor } = primed;
  clearTimeout(timer);
  primed = null;
  if (primedFor !== postID) {
    discard(el);
    return null;
  }
  forgetOffPage(el);
  return el;
}
