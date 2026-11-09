"use client";

import { useEffect, useRef, type AudioHTMLAttributes, type VideoHTMLAttributes } from "react";
import { playWithSound } from "@/lib/autoplay";

/*
 * Next.js keeps recently visited pages alive in the background (hidden, not
 * unmounted) so going Back is instant. A hidden <video> or <audio> would keep
 * playing, so these pause themselves whenever their page is hidden or left.
 *
 * `autoStart` begins playback, with sound, as soon as the page shows. Clicking
 * into a post counts as interaction, so browsers allow sound; on a cold page load
 * a browser may refuse, and the sound then comes on at the first click or key.
 */

function useManagedMedia<T extends HTMLMediaElement>(autoStart: boolean) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    const stopWaiting = el && autoStart ? playWithSound(el) : undefined;
    return () => {
      stopWaiting?.();
      el?.pause();
    };
  }, [autoStart]);
  return ref;
}

export function Video({ autoStart = false, ...props }: VideoHTMLAttributes<HTMLVideoElement> & { autoStart?: boolean }) {
  const ref = useManagedMedia<HTMLVideoElement>(autoStart);
  return <video ref={ref} {...props} />;
}

export function Audio({ autoStart = false, ...props }: AudioHTMLAttributes<HTMLAudioElement> & { autoStart?: boolean }) {
  const ref = useManagedMedia<HTMLAudioElement>(autoStart);
  return <audio ref={ref} {...props} />;
}
