"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { markReadAction, sendAction } from "@/app/(app)/network/actions";
import { personHref } from "@/lib/people";
import Avatar from "./Avatar";

export type InboxThread = {
  id: string;
  name: string;
  imageUrl?: string;
  profileID?: string;
  lastMessage: string;
  time: string;
  unread: number;
};

export type OpenThread = {
  id: string;
  name: string;
  imageUrl?: string;
  profileID?: string;
  messages: {
    id: string;
    fromMe: boolean;
    text: string;
    at: number;
    time?: string;
    attachmentType?: "image" | "video" | "document" | "post";
    attachmentUrl?: string;
    postID?: string;
  }[];
};

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

  // Pick up new messages while the page is open.
  useEffect(() => {
    if (!canSend) return;
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") router.refresh();
    }, REFRESH_MS);
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
              <Avatar name={open.name} src={open.imageUrl} size="md" />
              {open.profileID ? (
                <Link href={personHref(open.name, open.profileID)} className="font-semibold hover:underline">
                  {open.name}
                </Link>
              ) : (
                <p className="font-semibold">{open.name}</p>
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
                return (
                  <div key={m.id} className="contents">
                    {stamp && <p className="my-2 text-center text-xs text-muted">{m.time}</p>}
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
                      <Link href={`/post/${m.postID}`} className={`${bubble} underline`}>
                        Shared a post
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
                  placeholder={canSend ? `Message ${open.name.split(" ")[0]}` : "Connect CloudKit to send messages."}
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
