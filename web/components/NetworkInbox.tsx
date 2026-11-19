"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { markReadAction, sendAction, setGroupPhotoAction } from "@/app/(app)/network/actions";
import { personHref } from "@/lib/people";
import { preparePhoto } from "@/lib/preparePhoto";
import Avatar from "./Avatar";
import { CameraGlyph, ComposeGlyph } from "./icons";

export type InboxThread = {
  id: string;
  name: string;
  imageUrl?: string;
  profileID?: string;
  lastMessage: string;
  time: string;
  unread: number;
  /** Group chats: no profile to link to, and a head count under the name. */
  isGroup?: boolean;
  memberCount?: number;
};

export type OpenThread = {
  id: string;
  name: string;
  imageUrl?: string;
  profileID?: string;
  isGroup?: boolean;
  memberCount?: number;
  messages: {
    id: string;
    fromMe: boolean;
    text: string;
    at: number;
    time?: string;
    /** Group chats: who sent a received message, shown above its bubble. */
    senderName?: string;
    attachmentType?: "image" | "video" | "document" | "post";
    attachmentUrl?: string;
    postID?: string;
    /** The shared post's picture, title and page, when it's still on Nexus. */
    post?: { title: string; imageUrl?: string; href: string };
  }[];
};

/**
 * A group's picture in the thread header. Any member can click it to choose a new photo
 * or remove the current one. The new picture shows right away while it saves.
 */
function GroupPhoto({ threadID, name, src, onError }: { threadID: string; name: string; src?: string; onError: (message: string | null) => void }) {
  const router = useRouter();
  const [menu, setMenu] = useState(false);
  const [saving, startSave] = useTransition();
  // What was just chosen (null = removed), until the page brings back the saved picture.
  const [pending, setPending] = useState<{ from?: string; value: string | null } | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const shown = pending && pending.from === src ? pending.value : (src ?? null);

  function save(form: FormData, local: string | null) {
    setMenu(false);
    onError(null);
    setPending({ from: src, value: local });
    startSave(async () => {
      const res = await setGroupPhotoAction(threadID, form);
      if (!res.ok) {
        setPending(null);
        return onError(res.message);
      }
      router.refresh();
    });
  }

  async function choose(file: File | undefined) {
    if (!file) return;
    try {
      const ready = await preparePhoto(file, 800, "group.jpg");
      const form = new FormData();
      form.set("photo", ready);
      save(form, URL.createObjectURL(ready));
    } catch {
      setMenu(false);
      onError("That photo couldn't be read. Try a JPEG or PNG.");
    }
  }

  function remove() {
    const form = new FormData();
    form.set("remove", "1");
    save(form, null);
  }

  return (
    <div className="relative shrink-0">
      <button
        type="button"
        onClick={() => setMenu((m) => !m)}
        disabled={saving}
        aria-label="Change group photo"
        aria-expanded={menu}
        title="Change group photo"
        className="group relative block rounded-full"
      >
        <Avatar name={name} src={shown ?? undefined} size="md" />
        <span
          className={`absolute inset-0 flex items-center justify-center rounded-full bg-black/45 text-white transition ${
            saving ? "opacity-100" : "opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100"
          }`}
        >
          {saving ? <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" /> : <CameraGlyph className="h-5 w-5" />}
        </span>
      </button>
      <input
        ref={input}
        type="file"
        accept="image/jpeg,image/png,image/heic,image/*"
        tabIndex={-1}
        className="sr-only"
        onChange={(e) => {
          choose(e.target.files?.[0]);
          e.target.value = "";
        }}
      />
      {menu && (
        <>
          {/* Clicking anywhere else closes the menu. */}
          <button type="button" aria-label="Close menu" className="fixed inset-0 z-30 cursor-default" onClick={() => setMenu(false)} />
          <div role="menu" className="absolute left-0 top-full z-40 mt-2 w-48 overflow-hidden rounded-xl border border-border bg-background py-1 shadow-lg">
            <button
              type="button"
              role="menuitem"
              onClick={() => {
                setMenu(false);
                input.current?.click();
              }}
              className="block w-full px-4 py-2 text-left text-sm hover:bg-surface"
            >
              {shown ? "Choose new photo" : "Add group photo"}
            </button>
            {shown && (
              <button type="button" role="menuitem" onClick={remove} className="block w-full px-4 py-2 text-left text-sm text-red-500 hover:bg-surface">
                Remove photo
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
}

/** How often an open inbox checks for new messages. */
const REFRESH_MS = 15_000;

/**
 * Messages, desktop-mail style: conversations on the left, the open one on the right.
 * The open thread is in the URL (?c=…), so it survives a reload and can be linked to.
 * On narrow screens the list fills the page and a thread opens over it, with Back.
 */
export default function NetworkInbox({
  threads,
  open,
  openOnPhone,
  canSend,
  notice,
}: {
  threads: InboxThread[];
  open: OpenThread | null;
  /** Whether a thread was picked (phones show the list until one is). */
  openOnPhone: boolean;
  canSend: boolean;
  /** Shown in the right pane when there's no thread to open (signed out, not linked, no messages yet). */
  notice?: { title: string; body: string; href?: string; cta?: string };
}) {
  const router = useRouter();
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, startSend] = useTransition();
  const bottom = useRef<HTMLDivElement>(null);
  const openID = open?.id;
  const openUnread = threads.find((t) => t.id === openID)?.unread ?? 0;

  // Opening a thread marks it read, like the app.
  useEffect(() => {
    if (!canSend || !openID || openUnread === 0) return;
    markReadAction(openID).then(() => router.refresh());
  }, [canSend, openID, openUnread, router]);

  // Newest message in view.
  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [openID, open?.messages.length]);

  // Pick up new messages while the page is open. Each check is one small request; the
  // page itself is only rebuilt when something in the conversations has changed.
  useEffect(() => {
    if (!canSend) return;
    let last: string | null | undefined;
    const check = async () => {
      if (document.visibilityState !== "visible") return;
      try {
        const res = await fetch("/api/network/pulse", { cache: "no-store" });
        if (!res.ok) return;
        const { pulse } = (await res.json()) as { pulse: string | null };
        if (last !== undefined && pulse !== last) router.refresh();
        last = pulse;
      } catch {
        /* offline for a moment: try again on the next tick */
      }
    };
    check();
    const timer = setInterval(check, REFRESH_MS);
    return () => clearInterval(timer);
  }, [canSend, router]);

  function send() {
    const text = draft.trim();
    if (!text || !openID || sending) return;
    setError(null);
    startSend(async () => {
      const res = await sendAction(openID, text);
      if (!res.ok) return setError(res.message);
      setDraft("");
      router.refresh();
    });
  }

  return (
    <div className="grid h-[calc(100dvh-7rem)] min-h-[420px] min-w-0 overflow-hidden rounded-2xl border border-border md:grid-cols-[minmax(16rem,22rem)_minmax(0,1fr)]">
      {/* Conversation list */}
      <ul className={`min-h-0 overflow-y-auto border-border md:block md:border-r ${openOnPhone ? "hidden" : "block"}`}>
        <li className="p-3">
          <Link
            href="/network/new"
            className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-brand text-[15px] font-semibold text-white transition hover:brightness-110 active:scale-[0.99]"
          >
            <ComposeGlyph className="h-5 w-5" />
            New message
          </Link>
        </li>
{threads.length === 0 && (
          <li className="px-4 py-6 text-sm text-muted">
            {/* On phones only this pane shows, so the notice goes here too. */}
            <span className="md:hidden">{notice ? `${notice.title}. ${notice.body}` : "No conversations yet."}</span>
            <span className="hidden md:inline">No conversations yet.</span>
            {notice?.href && notice.cta && (
              <Link href={notice.href} className="mt-3 block w-fit rounded-full bg-brand px-4 py-1.5 text-sm font-semibold text-white md:hidden">
                {notice.cta}
              </Link>
            )}
          </li>
        )}
        {threads.map((t) => {
          const selected = t.id === openID;
          return (
            <li key={t.id}>
              <Link
                href={`/network?c=${encodeURIComponent(t.id)}`}
                scroll={false}
                aria-current={selected ? "true" : undefined}
                className={`flex w-full items-center gap-3 px-3 py-3 text-left transition ${selected ? "md:bg-brand/10" : "hover:bg-surface"}`}
              >
                <Avatar name={t.name} src={t.imageUrl} size="lg" />
                <span className="min-w-0 flex-1">
                  <span className="flex items-baseline justify-between gap-3">
                    <span className={`truncate ${t.unread ? "font-semibold" : ""}`}>{t.name}</span>
                    <span className="shrink-0 text-xs text-muted">{t.time}</span>
                  </span>
                  <span className={`mt-0.5 block truncate text-sm ${t.unread ? "text-foreground/85" : "text-muted"}`}>{t.lastMessage}</span>
                </span>
                {t.unread > 0 && <span aria-label={`${t.unread} unread`} className="h-2.5 w-2.5 shrink-0 rounded-full bg-brand" />}
              </Link>
            </li>
          );
        })}
      </ul>

      {/* Open conversation */}
      <section className={`min-h-0 min-w-0 flex-col md:flex ${openOnPhone ? "flex" : "hidden"}`}>
        {open ? (
          <>
            <header className="flex items-center gap-3 border-b border-border px-4 py-3">
              <Link href="/network" className="text-sm font-semibold text-brand md:hidden">
                ‹ Back
              </Link>
              {open.isGroup && canSend ? (
                <GroupPhoto key={open.id} threadID={open.id} name={open.name} src={open.imageUrl} onError={setError} />
              ) : (
                <Avatar name={open.name} src={open.imageUrl} size="md" />
              )}
              {open.profileID ? (
                <Link href={personHref(open.name, open.profileID)} className="font-semibold hover:underline">
                  {open.name}
                </Link>
              ) : (
                <span className="min-w-0">
                  <p className="truncate font-semibold">{open.name}</p>
                  {open.isGroup && open.memberCount ? <p className="text-xs text-muted">{open.memberCount} people</p> : null}
                </span>
              )}
            </header>
            <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-4">
              <div className="mt-auto" />
              {open.messages.map((m, i) => {
                const prev = open.messages[i - 1];
                // A timestamp above the first message and after any gap of an hour or more.
                const stamp = m.time && (!prev || m.at - prev.at > 60 * 60 * 1000);
                const bubble = `max-w-[75%] rounded-2xl px-3.5 py-2 text-sm ${
                  m.fromMe ? "self-end rounded-br-md bg-brand text-white" : "self-start rounded-bl-md bg-surface"
                }`;
                // Group chats: name the sender when they change (or after a time gap).
                const sender = m.senderName && (stamp || !prev || prev.senderName !== m.senderName || prev.fromMe) ? m.senderName : null;
                return (
                  <div key={m.id} className="contents">
                    {stamp && <p className="my-2 text-center text-xs text-muted">{m.time}</p>}
                    {sender && <p className="ml-3 self-start text-xs text-muted">{sender}</p>}
                    {m.attachmentType === "image" && m.attachmentUrl && (
                      <a href={m.attachmentUrl} target="_blank" rel="noopener noreferrer" className={m.fromMe ? "self-end" : "self-start"}>
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={m.attachmentUrl} alt="Photo" className="max-h-72 max-w-[75%] rounded-2xl object-cover" />
                      </a>
                    )}
                    {m.attachmentType === "video" && m.attachmentUrl && (
                      <video src={m.attachmentUrl} controls className={`max-h-72 max-w-[75%] rounded-2xl ${m.fromMe ? "self-end" : "self-start"}`} />
                    )}
                    {m.attachmentType === "document" && m.attachmentUrl && (
                      <a href={m.attachmentUrl} target="_blank" rel="noopener noreferrer" className={`${bubble} underline`}>
                        📎 Attachment
                      </a>
                    )}
                    {m.attachmentType === "post" && m.postID && (
                      // Like the app's bubble: the post's artwork at its own shape, title underneath.
                      <Link
                        href={m.post?.href ?? `/post/${m.postID}`}
                        className={`flex w-[200px] max-w-[75%] flex-col items-center gap-2 rounded-[20px] p-2.5 transition hover:brightness-95 ${
                          m.fromMe ? "self-end bg-brand text-white" : "self-start bg-surface"
                        }`}
                      >
                        {m.post?.imageUrl ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={m.post.imageUrl} alt="" className="max-h-72 w-full rounded-[10px] object-contain" />
                        ) : (
                          <div className="aspect-[7/9] w-full rounded-[10px] bg-foreground/15" />
                        )}
                        <span className="line-clamp-2 text-center text-sm font-semibold">{m.post?.title ?? "Shared post"}</span>
                      </Link>
                    )}
                    {m.text && <p className={`${bubble} whitespace-pre-line break-words`}>{m.text}</p>}
                  </div>
                );
              })}
              <div ref={bottom} />
            </div>
            <form
              className="border-t border-border p-3"
              onSubmit={(e) => {
                e.preventDefault();
                send();
              }}
            >
              {error && <p className="mb-2 text-sm text-red-500">{error}</p>}
              <div className="flex gap-2">
                <input
                  value={draft}
                  disabled={!canSend}
                  maxLength={4000}
                  onChange={(e) => setDraft(e.target.value)}
                  placeholder={canSend ? `Message ${open.isGroup ? open.name : open.name.split(" ")[0]}` : "Connect CloudKit to send messages."}
                  className="min-w-0 flex-1 rounded-full border border-border bg-background px-4 py-2 text-sm outline-none focus:border-brand disabled:opacity-60"
                />
                <button
                  type="submit"
                  disabled={!canSend || !draft.trim() || sending}
                  className="rounded-full bg-brand px-4 py-2 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-50"
                >
                  {sending ? "…" : "Send"}
                </button>
              </div>
            </form>
          </>
        ) : notice ? (
          <div className="m-auto max-w-sm space-y-3 p-6 text-center">
            <p className="text-lg font-semibold">{notice.title}</p>
            <p className="text-sm text-muted">{notice.body}</p>
            {notice.href && notice.cta && (
              <Link href={notice.href} className="inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
                {notice.cta}
              </Link>
            )}
          </div>
        ) : (
          <p className="m-auto text-muted">Select a conversation.</p>
        )}
      </section>
    </div>
  );
}

