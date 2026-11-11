import { lookup, modify, type CKRecord } from "./client";

/*
 * Connections between Nexus members, from the same CloudKit records the app uses
 * (ConnectionsManager.swift). One `Connection` record per direction, named
 * `Connection_<from>_<to>` and written only by its sender:
 *
 *   fromUserID, toUserID (raw user record names), fromName, kind ("request"/"accept"),
 *   createdDate
 *
 *   I sent one, they haven't  → "requested"
 *   They sent one, I haven't  → "incoming" (button reads Accept)
 *   Both exist                → "connected"
 *
 * Never cached: private to the two people. Every function takes the signed-in
 * visitor's own user record name and only writes or deletes the visitor's own edge.
 */

export type ConnectionState = "none" | "requested" | "incoming" | "connected";

/** The bare CloudKit user record name, like the app's canonicalMessagingID. */
export const rawUserID = (id: string) => id.replace(/^UserProfile_/, "");

const edgeName = (from: string, to: string) => `Connection_${rawUserID(from)}_${rawUserID(to)}`;

async function edgeExists(from: string, to: string): Promise<boolean> {
  const r: CKRecord | null = await lookup(edgeName(from, to));
  return !!r && r.recordType === "Connection";
}

/** Where the visitor stands with `other`. "none" if CloudKit can't be read. */
export async function connectionState(me: string, other: string): Promise<ConnectionState> {
  try {
    const [out, inc] = await Promise.all([edgeExists(me, other), edgeExists(other, me)]);
    return out && inc ? "connected" : out ? "requested" : inc ? "incoming" : "none";
  } catch (error) {
    console.error("[connections] state:", error instanceof Error ? error.message : error);
    return "none";
  }
}

/**
 * Sends a request to `other`, or accepts theirs if one is waiting, by writing the
 * visitor's own edge. The `kind` drives the push banner on the other person's phone.
 */
export async function connect(me: string, myName: string, other: string): Promise<ConnectionState> {
  const from = rawUserID(me);
  const to = rawUserID(other);
  if (!from || !to || from === to) throw new Error("Can't connect with yourself.");
  const theyAsked = await edgeExists(to, from).catch(() => false);
  await modify([
    {
      kind: "save",
      recordType: "Connection",
      recordName: edgeName(from, to),
      fields: {
        fromUserID: { value: from, type: "STRING" },
        toUserID: { value: to, type: "STRING" },
        fromName: { value: myName, type: "STRING" },
        kind: { value: theyAsked ? "accept" : "request", type: "STRING" },
        createdDate: { value: Date.now(), type: "TIMESTAMP" },
      },
    },
  ]);
  return theyAsked ? "connected" : "requested";
}

/** Withdraws the visitor's request to, or disconnects from, `other` (deletes only their own edge). */
export async function disconnect(me: string, other: string): Promise<ConnectionState> {
  await modify([{ kind: "delete", recordName: edgeName(me, other) }]);
  return (await edgeExists(other, me).catch(() => false)) ? "incoming" : "none";
}
