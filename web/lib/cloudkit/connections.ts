import { modify, lookup, queryWhere, str } from "./client";

/*
 * Private, mutual connections, from the same CloudKit `Connection` records the app
 * uses (ConnectionsManager.swift). One record per direction, named
 * `Connection_<from>_<to>` (raw user record names):
 *
 *   fromUserID, toUserID, fromName, kind ("request" | "accept"), createdDate
 *
 *   I wrote an edge, they haven't   -> requested
 *   They wrote one, I haven't       -> incoming (shows "Accept")
 *   Both edges exist                -> connected
 *
 * Accepting writes my own edge back; withdrawing or disconnecting deletes my own edge.
 * Never cached and never shown as a count, like the app.
 */

export type ConnectionState = "none" | "requested" | "incoming" | "connected";

const raw = (id: string) => id.replace(/^UserProfile_/, "");
const edgeName = (from: string, to: string) => `Connection_${raw(from)}_${raw(to)}`;

/** Where the visitor stands with one person: two lookups, one per direction. */
export async function connectionState(me: string, other: string): Promise<ConnectionState> {
  const [mine, theirs] = await Promise.all([lookup(edgeName(me, other)), lookup(edgeName(other, me))]);
  if (mine && theirs) return "connected";
  if (mine) return "requested";
  if (theirs) return "incoming";
  return "none";
}

/** Everyone the visitor is connected to, and everyone waiting on their answer (raw user record names). */
export async function connectionLists(me: string): Promise<{ connected: string[]; pending: string[] }> {
  const user = raw(me);
  const [outgoing, incoming] = await Promise.all([
    queryWhere("Connection", "fromUserID", user, ["toUserID"]),
    queryWhere("Connection", "toUserID", user, ["fromUserID"]),
  ]);
  const out = new Set(outgoing.map((r) => raw(str(r, "toUserID"))).filter(Boolean));
  const inn = new Set(incoming.map((r) => raw(str(r, "fromUserID"))).filter(Boolean));
  return {
    connected: [...out].filter((id) => inn.has(id)),
    pending: [...inn].filter((id) => !out.has(id)),
  };
}

/**
 * How many people someone is connected to (both ways). Zero when the count can't be
 * read, e.g. the `Connection` record type isn't in this CloudKit environment yet.
 */
export async function connectionCount(user: string): Promise<number> {
  try {
    return (await connectionLists(user)).connected.length;
  } catch {
    return 0;
  }
}

/** Sends a request, or accepts theirs when one is waiting. Returns the new state. */
export async function connectWith(me: string, myName: string, other: string): Promise<ConnectionState> {
  const from = raw(me);
  const to = raw(other);
  if (!to || to === from) throw new Error("You can't connect with yourself.");
  const incoming = await lookup(edgeName(to, from));
  await modify([
    {
      kind: "save",
      recordType: "Connection",
      recordName: edgeName(from, to),
      fields: {
        fromUserID: { value: from, type: "STRING" },
        toUserID: { value: to, type: "STRING" },
        fromName: { value: myName || "Someone", type: "STRING" },
        kind: { value: incoming ? "accept" : "request", type: "STRING" },
        createdDate: { value: Date.now(), type: "TIMESTAMP" },
      },
    },
  ]);
  return incoming ? "connected" : "requested";
}

/** Withdraws a request or disconnects, by deleting the visitor's own edge. */
export async function disconnectFrom(me: string, other: string): Promise<void> {
  await modify([{ kind: "delete", recordName: edgeName(me, other) }]);
}
