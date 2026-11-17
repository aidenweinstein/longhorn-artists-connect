import type { ShareTypeID } from "./sharePost";

/**
 * Share drafts, kept in this browser (IndexedDB), as the app keeps its drafts on the
 * phone. A draft holds every field of the form, picked files included, so resuming one
 * doesn't mean finding the video again. Browser only: nothing here reaches the server.
 */

export type ShareDraft = {
  id: string;
  type: ShareTypeID;
  title: string;
  savedAt: number;
  /** The form's fields by name (see useDraftField). Files are stored as they are. */
  fields: Record<string, unknown>;
};

const DB = "nexus-share-drafts";
const STORE = "drafts";

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE, { keyPath: "id" });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function run<T>(mode: IDBTransactionMode, work: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  try {
    return await new Promise<T>((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const req = work(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error ?? req.error);
      tx.onabort = () => reject(tx.error ?? req.error);
    });
  } finally {
    db.close();
  }
}

/** Every draft, newest first. */
export async function listDrafts(): Promise<ShareDraft[]> {
  const all = await run<ShareDraft[]>("readonly", (s) => s.getAll() as IDBRequest<ShareDraft[]>);
  return all.sort((a, b) => b.savedAt - a.savedAt);
}

export async function getDraft(id: string): Promise<ShareDraft | null> {
  return (await run<ShareDraft | undefined>("readonly", (s) => s.get(id) as IDBRequest<ShareDraft | undefined>)) ?? null;
}

export async function deleteDraft(id: string): Promise<void> {
  await run("readwrite", (s) => s.delete(id));
}

const hasFile = (v: unknown): boolean =>
  v instanceof Blob || (Array.isArray(v) ? v.some(hasFile) : !!v && typeof v === "object" && Object.values(v).some(hasFile));

/**
 * Saves (or updates) a draft. If the browser hasn't room for its files, the draft is saved
 * without the fields that hold files, and `filesKept` is false.
 */
export async function saveDraft(draft: ShareDraft): Promise<{ filesKept: boolean }> {
  try {
    await run("readwrite", (s) => s.put(draft));
    return { filesKept: true };
  } catch (error) {
    if (!(error instanceof DOMException && error.name === "QuotaExceededError")) throw error;
    const fields = Object.fromEntries(Object.entries(draft.fields).filter(([, v]) => !hasFile(v)));
    await run("readwrite", (s) => s.put({ ...draft, fields }));
    return { filesKept: false };
  }
}
