/**
 * One sound at a time: whenever any video or song on the site starts, every other
 * one pauses. Covers elements on the page and ones held off-page (the video a
 * click starts for Safari, see primedPlayback.ts), which page-level events miss.
 */
const offPage = new Set<HTMLMediaElement>();
let installed = false;

function pauseOthers(playing: EventTarget | null) {
  const all = new Set<HTMLMediaElement>([...document.querySelectorAll<HTMLMediaElement>("video, audio"), ...offPage]);
  for (const m of all) if (m !== playing && !m.paused) m.pause();
}

function install() {
  if (installed || typeof document === "undefined") return;
  installed = true;
  // "play" doesn't bubble, so listen in the capture phase.
  document.addEventListener("play", (e) => pauseOthers(e.target), true);
}

/** Includes an element the page can't see (not in the document) in the one-at-a-time rule. */
export function trackOffPage(el: HTMLMediaElement) {
  install();
  if (offPage.has(el)) return;
  offPage.add(el);
  el.addEventListener("play", () => {
    if (!el.isConnected) pauseOthers(el);
  });
}

export function forgetOffPage(el: HTMLMediaElement) {
  offPage.delete(el);
}

/**
 * Starts media with sound. Browsers refuse sound until the visitor has clicked,
 * tapped or pressed a key on the page; when that happens the media starts muted
 * and its sound comes on at the visitor's first click, tap or keypress anywhere.
 * Returns a cleanup that removes the waiting listener.
 */
const soundCameOnAt = new WeakMap<HTMLMediaElement, number>();

/**
 * True right after the visitor's click or tap turned on sound the browser had held
 * back. The player uses it so that click only unmutes, rather than also pausing.
 */
export function justGotSound(el: HTMLMediaElement) {
  const at = soundCameOnAt.get(el);
  return at !== undefined && performance.now() - at < 600;
}

export function playWithSound(el: HTMLMediaElement): () => void {
  install();
  let waiting = false;
  const unmute = () => {
    if (waiting) {
      waiting = false;
      el.muted = false;
      soundCameOnAt.set(el, performance.now());
    }
    remove();
  };
  const events = ["pointerdown", "keydown", "touchstart"] as const;
  const remove = () => events.forEach((e) => window.removeEventListener(e, unmute, true));

  el.muted = false;
  el.play().catch(() => {
    el.muted = true;
    el.play().catch(() => {});
    waiting = true;
    events.forEach((e) => window.addEventListener(e, unmute, { capture: true, passive: true }));
  });
  return remove;
}
