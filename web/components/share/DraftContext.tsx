"use client";

import { useSearchParams } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react";
import { loadPostForEdit } from "@/app/(app)/share/editActions";
import { deleteDraft, getDraft, saveDraft } from "@/lib/shareDrafts";
import { syncEarlyUploads } from "@/lib/shareUpload";
import type { ShareTypeID } from "@/lib/sharePost";

/**
 * Lets a Share form be saved as a draft and resumed (/share/<type>?draft=<id>). Each
 * form keeps its fields with useDraftField instead of useState: the field starts from the
 * draft being resumed, and its current value is what Save draft stores.
 *
 * /share/<type>?edit=<postID> opens one of your posts the same way, filled in from the
 * post; `kept` lists the form's file fields the post already has files for.
 */

type Ctx = {
  type: ShareTypeID;
  loaded: Record<string, unknown>;
  /** Notes a field's current value, for Save draft. */
  record: (key: string, value: unknown) => void;
  /** Every field's current value. */
  snapshot: () => Record<string, unknown>;
  draftID: string | null;
  setDraftID: (id: string) => void;
  editing: { postID: string; kept: Set<string> } | null;
};

const DraftCtx = createContext<Ctx | null>(null);

export function DraftProvider({ type, children }: { type: ShareTypeID; children: ReactNode }) {
  const params = useSearchParams();
  const wanted = params.get("draft");
  const editID = params.get("edit");
  // undefined while a draft or post is still being read.
  const [loaded, setLoaded] = useState<Record<string, unknown> | undefined>(wanted || editID ? undefined : {});
  const [draftID, setDraftID] = useState<string | null>(null);
  const [editing, setEditing] = useState<Ctx["editing"]>(null);
  const [editError, setEditError] = useState<string | null>(null);
  const values = useRef<Record<string, unknown>>({});
  const [watchers] = useState(() => new Set<() => void>());
  const record = useCallback((key: string, value: unknown) => {
    if (values.current[key] === value) return;
    values.current[key] = value;
    watchers.forEach((w) => w());
  }, [watchers]);
  const snapshot = useCallback(() => ({ ...values.current }), []);

  useEffect(() => {
    if (!editID) return;
    let live = true;
    loadPostForEdit(editID)
      .then((res) => {
        if (!live) return;
        if (!res.ok || res.type !== type) {
          setEditError(res.ok ? "This post can't be edited here." : res.message);
          return;
        }
        setEditing({ postID: editID, kept: new Set(res.kept) });
        setLoaded(res.fields);
      })
      .catch(() => live && setEditError("Couldn't open this post. Try again in a moment."));
    return () => {
      live = false;
    };
  }, [editID, type]);

  useEffect(() => {
    if (!wanted || editID) return;
    let live = true;
    getDraft(wanted)
      .then((d) => {
        if (!live) return;
        const match = d && d.type === type ? d : null;
        setDraftID(match?.id ?? null);
        setLoaded(match?.fields ?? {});
      })
      .catch(() => live && setLoaded({}));
    return () => {
      live = false;
    };
  }, [wanted, editID, type]);

  if (editError) return <p className="px-6 py-10 text-muted">{editError}</p>;
  if (!loaded) return <p className="px-6 py-10 text-muted">{editID ? "Opening post…" : "Opening draft…"}</p>;
  return (
    <DraftCtx.Provider value={{ type, loaded, record, snapshot, draftID, setDraftID, editing }}>
      {children}
      <EarlyUploads watchers={watchers} snapshot={snapshot} editPostID={editing?.postID ?? null} />
    </DraftCtx.Provider>
  );
}

/** Every File anywhere in the form's fields (lists and small objects included). */
function filesIn(value: unknown, depth = 0, out: File[] = []): File[] {
  if (value instanceof File) out.push(value);
  else if (depth < 4 && Array.isArray(value)) value.forEach((v) => filesIn(v, depth + 1, out));
  else if (depth < 4 && value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    Object.values(value).forEach((v) => filesIn(v, depth + 1, out));
  }
  return out;
}

/**
 * Starts uploading each video and audio file as soon as it's picked (lib/shareUpload.ts),
 * and stops when it's removed or replaced, or the form is left. Rendered after the form,
 * so its fields have recorded their values first.
 */
function EarlyUploads({ watchers, snapshot, editPostID }: { watchers: Set<() => void>; snapshot: () => Record<string, unknown>; editPostID: string | null }) {
  useEffect(() => {
    let queued = false;
    const sync = () => syncEarlyUploads(filesIn(snapshot()), editPostID);
    const schedule = () => {
      if (queued) return;
      queued = true;
      queueMicrotask(() => {
        queued = false;
        sync();
      });
    };
    sync();
    watchers.add(schedule);
    return () => {
      watchers.delete(schedule);
      syncEarlyUploads([], editPostID);
    };
  }, [watchers, snapshot, editPostID]);
  return null;
}

/** useState for a Share form field that drafts save and restore. Keys are unique per form. */
export function useDraftField<T>(key: string, initial: T | (() => T)): [T, Dispatch<SetStateAction<T>>] {
  const ctx = useContext(DraftCtx);
  const [value, setValue] = useState<T>(() =>
    ctx && key in ctx.loaded ? (ctx.loaded[key] as T) : typeof initial === "function" ? (initial as () => T)() : initial,
  );
  const record = ctx?.record;
  useEffect(() => {
    record?.(key, value);
  }, [record, key, value]);
  return [value, setValue];
}

/** Save draft for the Share page frame, and clearing the draft once its post is published. */
export function useDrafts() {
  const ctx = useContext(DraftCtx);
  const save = useCallback(async () => {
    if (!ctx) throw new Error("No draft context.");
    const id = ctx.draftID ?? crypto.randomUUID();
    const fields = ctx.snapshot();
    const title = typeof fields.title === "string" ? fields.title.trim() : "";
    const result = await saveDraft({ id, type: ctx.type, title, savedAt: Date.now(), fields });
    ctx.setDraftID(id);
    return result;
  }, [ctx]);
  const clear = useCallback(async () => {
    if (ctx?.draftID) await deleteDraft(ctx.draftID).catch(() => undefined);
  }, [ctx]);
  // Drafts are for new posts; editing saves straight to the post.
  return { available: !!ctx && !ctx.editing, resumed: !!ctx?.draftID, save, clear };
}

/** Editing a post: its ID, else null. */
export function useEditing(): string | null {
  return useContext(DraftCtx)?.editing?.postID ?? null;
}

const NONE: ReadonlySet<string> = new Set();
/** Editing: the form's file fields the post already has files for (they count as filled in). */
export function useKeptFiles(): ReadonlySet<string> {
  return useContext(DraftCtx)?.editing?.kept ?? NONE;
}
