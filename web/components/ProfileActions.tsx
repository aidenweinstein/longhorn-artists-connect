"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { connectAction, disconnectAction, messageAction } from "@/app/(app)/portfolio/[person]/actions";
import type { ConnectionState } from "@/lib/cloudkit/connections";

/**
 * Connect and Message, side by side under the person's info on someone else's
 * portfolio — the website's version of the app's ProfileActionButtons.
 * Connect → Requested → Connected, or Accept when they asked first. Clicking
 * Requested or Connected asks before withdrawing or disconnecting.
 */
export default function ProfileActions({ profileID, name, initialState }: { profileID: string; name: string; initialState: ConnectionState }) {
  const router = useRouter();
  const [state, setState] = useState<ConnectionState>(initialState);
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [connecting, startConnect] = useTransition();
  const [messaging, startMessage] = useTransition();

  const first = name.split(" ")[0] || "them";
  const label = { none: "Connect", requested: "Requested", incoming: "Accept", connected: "Connected" }[state];
  const filled = state === "none" || state === "incoming";

  function onConnect() {
    setError(null);
    if (state === "requested" || state === "connected") {
      setConfirming(true);
      return;
    }
    const before = state;
    setState(before === "incoming" ? "connected" : "requested");
    startConnect(async () => {
      const res = await connectAction(profileID);
      if (res.ok) setState(res.state);
      else {
        setState(before);
        setError(res.message);
      }
    });
  }

  function onDisconnect() {
    setConfirming(false);
    setError(null);
    const before = state;
    setState("none");
    startConnect(async () => {
      const res = await disconnectAction(profileID);
      if (res.ok) setState(res.state);
      else {
        setState(before);
        setError(res.message);
      }
    });
  }

  function onMessage() {
    setError(null);
    startMessage(async () => {
      const res = await messageAction(profileID);
      if (res.ok) router.push(`/network?c=${res.threadID}`);
      else setError(res.message);
    });
  }

  const box =
    "flex flex-1 items-center justify-center gap-2 rounded-[10px] px-4 py-2.5 text-sm font-semibold transition disabled:opacity-60";

  return (
    <div className="mt-5 max-w-md">
      <div className="flex gap-2.5">
        <button
          type="button"
          onClick={onConnect}
          disabled={connecting}
          aria-label={
            state === "requested"
              ? `Connection request to ${name} pending. Click to withdraw.`
              : state === "connected"
                ? `Connected with ${name}. Click to disconnect.`
                : state === "incoming"
                  ? `Accept ${name}'s connection request`
                  : `Connect with ${name}`
          }
          className={`${box} ${filled ? "bg-brand text-brand-foreground hover:brightness-110" : "bg-brand/12 text-brand hover:bg-brand/20"}`}
        >
          <ConnectGlyph state={state} />
          {label}
        </button>
        <button
          type="button"
          onClick={onMessage}
          disabled={messaging}
          aria-label={`Message ${name}`}
          className={`${box} bg-brand text-brand-foreground hover:brightness-110`}
        >
          <svg aria-hidden viewBox="0 0 20 20" className="h-4 w-4" fill="currentColor">
            <path d="M10 2.5c-4.4 0-8 3-8 6.8 0 2 1 3.8 2.7 5l-.6 2.9 3.1-1.6c.9.3 1.8.4 2.8.4 4.4 0 8-3 8-6.7S14.4 2.5 10 2.5Z" />
          </svg>
          {messaging ? "Opening…" : "Message"}
        </button>
      </div>

      {confirming && (
        <div role="dialog" aria-label="Confirm" className="mt-2.5 flex flex-wrap items-center gap-2 rounded-[10px] border border-border bg-surface px-3 py-2 text-sm">
          <span className="mr-auto">
            {state === "requested" ? `Withdraw your connection request to ${first}?` : `Remove ${first} from your connections?`}
          </span>
          <button type="button" onClick={() => setConfirming(false)} className="rounded-full px-3 py-1 font-medium text-muted hover:text-foreground">
            Cancel
          </button>
          <button type="button" onClick={onDisconnect} className="rounded-full bg-red-600 px-3 py-1 font-semibold text-white hover:bg-red-700">
            {state === "requested" ? "Withdraw" : "Disconnect"}
          </button>
        </div>
      )}

      {error && <p className="mt-2 text-sm text-red-500">{error}</p>}
    </div>
  );
}

function ConnectGlyph({ state }: { state: ConnectionState }) {
  if (state === "connected")
    return (
      <svg aria-hidden viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round">
        <path d="m4.5 10.5 3.5 3.5 7.5-8" />
      </svg>
    );
  if (state === "requested")
    return (
      <svg aria-hidden viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round">
        <circle cx="10" cy="10" r="7" />
        <path d="M10 6v4l2.5 1.5" />
      </svg>
    );
  return (
    <svg aria-hidden viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round">
      <circle cx="8" cy="6.5" r="3" />
      <path d="M2.5 16.5c.6-3 2.8-4.5 5.5-4.5s4.9 1.5 5.5 4.5M15.5 6.5v5M13 9h5" />
    </svg>
  );
}
