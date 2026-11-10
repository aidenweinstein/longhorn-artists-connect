"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { connectAction, disconnectAction, startConversationAction } from "@/app/(app)/network/actions";
import type { ConnectionState } from "@/lib/cloudkit/connections";

const LABEL: Record<ConnectionState, string> = { none: "Connect", requested: "Requested", incoming: "Accept", connected: "Connected" };

const box = "rounded-xl px-5 py-2 text-sm font-semibold transition disabled:opacity-60";
const filled = `${box} bg-brand text-white hover:brightness-110`;
const tinted = `${box} bg-brand/12 text-brand hover:bg-brand/20`;

/**
 * Connect: "Connect" → "Requested" → "Connected", or "Accept" when they asked first.
 * Requested and Connected ask before withdrawing or disconnecting, like the app.
 */
export function ConnectButton({
  profileID,
  name,
  initial,
  onChange,
}: {
  profileID: string;
  name: string;
  initial: ConnectionState;
  onChange?: (state: ConnectionState) => void;
}) {
  const router = useRouter();
  const [state, setState] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  function press() {
    setError(null);
    if (state === "requested" && !confirm(`Withdraw your connection request to ${name}?`)) return;
    if (state === "connected" && !confirm(`Remove ${name} from your connections?`)) return;
    start(async () => {
      const res = state === "none" || state === "incoming" ? await connectAction(profileID) : await disconnectAction(profileID);
      if (!res.ok) return setError(res.message);
      setState(res.state);
      onChange?.(res.state);
      router.refresh();
    });
  }

  return (
    <span className="flex flex-col">
      <button
        type="button"
        onClick={press}
        disabled={busy}
        aria-label={state === "none" ? `Connect with ${name}` : state === "incoming" ? `Accept ${name}'s connection request` : `${LABEL[state]} with ${name}`}
        className={state === "none" || state === "incoming" ? filled : tinted}
      >
        {LABEL[state]}
      </button>
      {error && <span className="mt-1 text-xs text-red-500">{error}</span>}
    </span>
  );
}

/** Message: opens the thread with this person in the inbox, starting it if it's new. */
export function MessageButton({ profileID }: { profileID: string }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  return (
    <span className="flex flex-col">
      <button
        type="button"
        disabled={busy}
        onClick={() =>
          start(async () => {
            setError(null);
            const res = await startConversationAction(profileID);
            if (!res.ok) return setError(res.message);
            router.push(`/network?c=${encodeURIComponent(res.threadID)}`);
          })
        }
        className={tinted}
      >
        Message
      </button>
      {error && <span className="mt-1 text-xs text-red-500">{error}</span>}
    </span>
  );
}

/** The two action boxes on someone else's portfolio. */
export default function ProfileActionButtons({ profileID, name, state }: { profileID: string; name: string; state: ConnectionState }) {
  return (
    <div className="flex items-start gap-2">
      <ConnectButton profileID={profileID} name={name} initial={state} />
      <MessageButton profileID={profileID} />
    </div>
  );
}
