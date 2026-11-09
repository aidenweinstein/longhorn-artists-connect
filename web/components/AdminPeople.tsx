"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Avatar from "./Avatar";
import {
  decideApplication,
  moveFeature,
  movePick,
  removePick,
  savePick,
  moveCollection,
  moveCollectionItem,
  removeCollection,
  removeCollectionItem,
  saveCollection,
  saveCollectionItem,
  postsFor,
  removeFeature,
  saveFeature,
  saveFeatures,
  type PickablePost,
} from "@/app/(app)/admin/people/actions";
import type { Application, Feature, FeaturedCollection, StaffPick } from "@/lib/featured";
import { getCategory } from "@/lib/categories";

export type AdminFeature = Feature & { imageUrl?: string };
type Person = { profileID: string; name: string; imageUrl?: string; roles?: string[] };
type Page = { slug: string; label: string; tags: string[] };
type CatalogPost = { id: string; title: string; creator: string; thumbnailUrl?: string; category: string };

/** What the editor is working on: a new or existing feature, possibly from an application. */
type Draft = {
  category: string;
  person: Person | null;
  blurb: string;
  postIDs: string[];
  applicationID?: string;
  /** The application being answered, shown for reference while editing. */
  application?: Application;
};

const btn = "rounded-full px-4 py-1.5 text-sm font-semibold transition disabled:opacity-50";
const quiet = `${btn} border border-border hover:bg-foreground/10`;
const primary = `${btn} bg-brand text-white hover:brightness-110`;
const date = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "America/Chicago" });

export default function AdminPeople({
  pages,
  applications,
  declined,
  features,
  directory,
  picks,
  collections,
  catalog,
}: {
  picks: StaffPick[];
  collections: FeaturedCollection[];
  catalog: CatalogPost[];
  pages: Page[];
  applications: Application[] | null;
  declined: Application[];
  features: Record<string, AdminFeature[]>;
  directory: Person[];
}) {
  const router = useRouter();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showDeclined, setShowDeclined] = useState(false);
  const [bulkFor, setBulkFor] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pickDraft, setPickDraft] = useState<{ postID: string | null; note: string } | null>(null);
  /** A post being added to (postID null) or edited in a collection. */
  const [itemDraft, setItemDraft] = useState<{ collectionID: string; postID: string | null; note: string } | null>(null);
  /** A collection being created (no id) or renamed. */
  const [collectionDraft, setCollectionDraft] = useState<{ id?: string; title: string; description: string } | null>(null);
  const postByID = useMemo(() => new Map(catalog.map((p) => [p.id, p])), [catalog]);
  const [pending, start] = useTransition();
  const label = (slug: string) => pages.find((p) => p.slug === slug)?.label ?? slug;

  function run(action: () => Promise<{ ok: true } | { ok: false; message: string }>, after?: () => void) {
    setError(null);
    setNotice(null);
    start(async () => {
      const res = await action();
      if (!res.ok) return setError(res.message);
      after?.();
      router.refresh();
    });
  }

  function editFrom(app: Application) {
    const person = directory.find((p) => p.profileID === app.profileID) ?? (app.profileID ? { profileID: app.profileID, name: app.name } : null);
    setDraft({ category: app.category, person, blurb: "", postIDs: [], applicationID: app.id, application: app });
  }

  return (
    <div className="mx-auto max-w-5xl space-y-10">
      <header>
        <h1 className="text-3xl font-bold">Manage</h1>
        <p className="mt-1 text-muted">People pages and Featured. Only admins can see this page, and changes show on the site right away.</p>
        {error && <p className="mt-3 rounded-xl bg-red-500/10 p-3 text-sm text-red-500">{error}</p>}
        {notice && <p className="mt-3 rounded-xl bg-brand/10 p-3 text-sm text-brand">{notice}</p>}
      </header>

      <section>
        <h2 className="text-xl font-semibold">Applications {applications && applications.length > 0 && <span className="text-muted">({applications.length})</span>}</h2>
        {applications === null ? (
          <p className="mt-3 text-muted">Couldn&rsquo;t load applications. Is the verification service deployed with the People update?</p>
        ) : applications.length === 0 ? (
          <p className="mt-3 text-muted">No new applications.</p>
        ) : (
          <ul className="mt-4 space-y-3">
            {applications.map((a) => (
              <ApplicationCard key={a.id} app={a} label={label(a.category)}>
                <button className={primary} disabled={pending} onClick={() => editFrom(a)}>
                  Feature
                </button>
                <button className={quiet} disabled={pending} onClick={() => run(() => decideApplication(a.id, "declined"))}>
                  Decline
                </button>
              </ApplicationCard>
            ))}
          </ul>
        )}
        {declined.length > 0 && (
          <div className="mt-4">
            <button className="text-sm text-muted hover:text-foreground" onClick={() => setShowDeclined((s) => !s)}>
              {showDeclined ? "Hide" : "Show"} declined ({declined.length})
            </button>
            {showDeclined && (
              <ul className="mt-3 space-y-3 opacity-80">
                {declined.map((a) => (
                  <ApplicationCard key={a.id} app={a} label={label(a.category)}>
                    <button className={quiet} disabled={pending} onClick={() => run(() => decideApplication(a.id, "pending"))}>
                      Move back to new
                    </button>
                  </ApplicationCard>
                ))}
              </ul>
            )}
          </div>
        )}
      </section>

      {pages.map((page) => {
        const list = features[page.slug] ?? [];
        return (
          <section key={page.slug}>
            <div className="flex items-center justify-between gap-4">
              <h2 className="text-xl font-semibold">
                {page.label} <span className="text-muted">({list.length})</span>
              </h2>
              <div className="flex shrink-0 gap-2">
                <button className={quiet} onClick={() => setBulkFor(page.slug)}>
                  + Add several
                </button>
                <button className={quiet} onClick={() => setDraft({ category: page.slug, person: null, blurb: "", postIDs: [] })}>
                  + Add someone
                </button>
              </div>
            </div>
            {list.length === 0 ? (
              <p className="mt-3 text-muted">No one featured yet.</p>
            ) : (
              <ul className="mt-4 divide-y divide-border rounded-2xl bg-surface">
                {list.map((f, i) => (
                  <li key={f.id} className="flex items-center gap-4 p-4">
                    <Avatar name={f.name} src={f.imageUrl} size="md" />
                    <div className="min-w-0 flex-1">
                      <p className="font-semibold">{f.name}</p>
                      <p className="truncate text-sm text-muted">
                        {f.blurb || "No blurb"} · {f.postIDs.length} {f.postIDs.length === 1 ? "post" : "posts"}
                      </p>
                    </div>
                    <div className="flex shrink-0 flex-wrap justify-end gap-1.5">
                      <button className={quiet} disabled={pending || i === 0} onClick={() => run(() => moveFeature(f.id, "up"))} aria-label="Move up">
                        ↑
                      </button>
                      <button className={quiet} disabled={pending || i === list.length - 1} onClick={() => run(() => moveFeature(f.id, "down"))} aria-label="Move down">
                        ↓
                      </button>
                      <button
                        className={quiet}
                        disabled={pending}
                        onClick={() =>
                          setDraft({
                            category: f.category,
                            person: { profileID: f.profileID, name: f.name, imageUrl: f.imageUrl },
                            blurb: f.blurb,
                            postIDs: f.postIDs,
                          })
                        }
                      >
                        Edit
                      </button>
                      <button
                        className={`${quiet} text-red-500`}
                        disabled={pending}
                        onClick={() => confirmRemove(f.name) && run(() => removeFeature(f.id))}
                      >
                        Remove
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        );
      })}

      <section id="featured" className="scroll-mt-4">
        <div className="flex items-center justify-between gap-4">
          <h2 className="text-xl font-semibold">
            Featured <span className="text-muted">({picks.length})</span>
          </h2>
          <button className={quiet} onClick={() => setPickDraft({ postID: null, note: "" })}>
            + Add a pick
          </button>
        </div>
        {picks.length === 0 ? (
          <p className="mt-3 text-muted">No picks yet.</p>
        ) : (
          <ul className="mt-4 divide-y divide-border rounded-2xl bg-surface">
            {picks.map((pick, i) => {
              const post = postByID.get(pick.postID);
              return (
                <li key={pick.postID} className="flex items-center gap-4 p-4">
                  <Thumb post={post} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">{post?.title ?? "Post no longer available"}</p>
                    <p className="truncate text-sm text-muted">
                      {post ? post.creator : "It won't show on Featured"}
                      {pick.note && ` · “${pick.note}”`}
                    </p>
                  </div>
                  <div className="flex shrink-0 flex-wrap justify-end gap-1.5">
                    <button className={quiet} disabled={pending || i === 0} onClick={() => run(() => movePick(pick.postID, "up"))} aria-label="Move up">
                      ↑
                    </button>
                    <button className={quiet} disabled={pending || i === picks.length - 1} onClick={() => run(() => movePick(pick.postID, "down"))} aria-label="Move down">
                      ↓
                    </button>
                    <button className={quiet} disabled={pending} onClick={() => setPickDraft({ postID: pick.postID, note: pick.note })}>
                      Edit note
                    </button>
                    <button
                      className={`${quiet} text-red-500`}
                      disabled={pending}
                      onClick={() => window.confirm(`Remove “${post?.title ?? "this post"}” from Featured?`) && run(() => removePick(pick.postID))}
                    >
                      Remove
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section id="collections" className="scroll-mt-4">
        <div className="flex items-center justify-between gap-4">
          <div>
            <h2 className="text-xl font-semibold">
              Collections <span className="text-muted">({collections.length})</span>
            </h2>
            <p className="text-sm text-muted">Named groups of posts shown on Featured, below the picks.</p>
          </div>
          <button className={quiet} onClick={() => setCollectionDraft({ title: "", description: "" })}>
            + New collection
          </button>
        </div>
        {collections.length === 0 ? (
          <p className="mt-3 text-muted">No collections yet.</p>
        ) : (
          <div className="mt-4 space-y-4">
            {collections.map((c, ci) => (
              <div key={c.id} className="rounded-2xl bg-surface">
                <div className="flex flex-wrap items-start justify-between gap-3 border-b border-border p-4">
                  <div className="min-w-0">
                    <p className="font-semibold">{c.title}</p>
                    {c.description && <p className="text-sm text-muted">{c.description}</p>}
                  </div>
                  <div className="flex shrink-0 flex-wrap justify-end gap-1.5">
                    <button className={quiet} disabled={pending || ci === 0} onClick={() => run(() => moveCollection(c.id, "up"))} aria-label="Move collection up">
                      ↑
                    </button>
                    <button className={quiet} disabled={pending || ci === collections.length - 1} onClick={() => run(() => moveCollection(c.id, "down"))} aria-label="Move collection down">
                      ↓
                    </button>
                    <button className={quiet} disabled={pending} onClick={() => setCollectionDraft({ id: c.id, title: c.title, description: c.description })}>
                      Rename
                    </button>
                    <button className={quiet} disabled={pending} onClick={() => setItemDraft({ collectionID: c.id, postID: null, note: "" })}>
                      + Add post
                    </button>
                    <button
                      className={`${quiet} text-red-500`}
                      disabled={pending}
                      onClick={() => window.confirm(`Delete the collection “${c.title}”? Its posts stay on Nexus.`) && run(() => removeCollection(c.id))}
                    >
                      Delete
                    </button>
                  </div>
                </div>
                {c.items.length === 0 ? (
                  <p className="p-4 text-sm text-muted">No posts yet. It won&rsquo;t show on Featured until it has one.</p>
                ) : (
                  <ul className="divide-y divide-border">
                    {c.items.map((item, i) => {
                      const post = postByID.get(item.postID);
                      return (
                        <li key={item.postID} className="flex items-center gap-4 p-4">
                          <Thumb post={post} />
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-semibold">{post?.title ?? "Post no longer available"}</p>
                            <p className="truncate text-sm text-muted">
                              {post ? post.creator : "It won't show on Featured"}
                              {item.note && ` · “${item.note}”`}
                            </p>
                          </div>
                          <div className="flex shrink-0 flex-wrap justify-end gap-1.5">
                            <button className={quiet} disabled={pending || i === 0} onClick={() => run(() => moveCollectionItem(c.id, item.postID, "up"))} aria-label="Move up">
                              ↑
                            </button>
                            <button
                              className={quiet}
                              disabled={pending || i === c.items.length - 1}
                              onClick={() => run(() => moveCollectionItem(c.id, item.postID, "down"))}
                              aria-label="Move down"
                            >
                              ↓
                            </button>
                            <button className={quiet} disabled={pending} onClick={() => setItemDraft({ collectionID: c.id, postID: item.postID, note: item.note })}>
                              Edit note
                            </button>
                            <button
                              className={`${quiet} text-red-500`}
                              disabled={pending}
                              onClick={() => window.confirm(`Remove “${post?.title ?? "this post"}” from ${c.title}?`) && run(() => removeCollectionItem(c.id, item.postID))}
                            >
                              Remove
                            </button>
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      {collectionDraft && (
        <CollectionEditor
          initial={collectionDraft}
          saving={pending}
          onCancel={() => setCollectionDraft(null)}
          onSave={(c) => run(() => saveCollection({ ...collectionDraft, ...c }), () => setCollectionDraft(null))}
        />
      )}

      {itemDraft && (
        <PickEditor
          initial={itemDraft}
          title={itemDraft.postID ? "Edit note" : `Add to ${collections.find((c) => c.id === itemDraft.collectionID)?.title ?? "collection"}`}
          catalog={catalog}
          picked={new Set(collections.find((c) => c.id === itemDraft.collectionID)?.items.map((i) => i.postID) ?? [])}
          saving={pending}
          onCancel={() => setItemDraft(null)}
          onSave={(postID, note) => run(() => saveCollectionItem(itemDraft.collectionID, postID, note), () => setItemDraft(null))}
        />
      )}

      {bulkFor && (
        <BulkAdder
          page={pages.find((p) => p.slug === bulkFor)!}
          directory={directory}
          onPage={new Set((features[bulkFor] ?? []).map((f) => f.profileID))}
          saving={pending}
          onCancel={() => setBulkFor(null)}
          onSave={(people) =>
            run(
              () => saveFeatures({ category: bulkFor, people: people.map((p) => ({ profileID: p.profileID, name: p.name })) }),
              () => {
                setNotice(`Added ${people.length} ${people.length === 1 ? "person" : "people"} to ${label(bulkFor)}. Use Edit to give them a blurb and posts.`);
                setBulkFor(null);
              },
            )
          }
        />
      )}

      {pickDraft && (
        <PickEditor
          initial={pickDraft}
          catalog={catalog}
          picked={new Set(picks.map((p) => p.postID))}
          saving={pending}
          onCancel={() => setPickDraft(null)}
          onSave={(postID, note) => run(() => savePick(postID, note), () => setPickDraft(null))}
        />
      )}

      {draft && (
        <Editor
          key={`${draft.category}-${draft.person?.profileID ?? "new"}-${draft.applicationID ?? ""}`}
          draft={draft}
          pages={pages}
          directory={directory}
          saving={pending}
          onCancel={() => setDraft(null)}
          onSave={(d) =>
            run(
              () =>
                saveFeature({
                  category: d.category,
                  profileID: d.person!.profileID,
                  name: d.person!.name,
                  blurb: d.blurb,
                  postIDs: d.postIDs,
                  applicationID: d.applicationID,
                }),
              () => setDraft(null),
            )
          }
        />
      )}
    </div>
  );
}

/** Removing is a one-click mistake otherwise. A plain confirm keeps it simple. */
function confirmRemove(name: string) {
  return window.confirm(`Remove ${name} from this page?`);
}

function ApplicationCard({ app, label, children }: { app: Application; label: string; children: React.ReactNode }) {
  return (
    <li className="rounded-2xl bg-surface p-4">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="rounded-full bg-brand/15 px-2.5 py-0.5 text-xs font-semibold text-brand">{label}</span>
        <span className="font-semibold">{app.name}</span>
        <span className="text-sm text-muted">
          {app.email} · {date.format(app.createdAt * 1000)}
          {!app.profileID && " · no linked Nexus account"}
        </span>
      </div>
      <p className="mt-2 whitespace-pre-line text-sm leading-relaxed text-foreground/85">{app.message}</p>
      {app.links && <p className="mt-2 whitespace-pre-line break-words text-sm text-brand">{app.links}</p>}
      <div className="mt-3 flex flex-wrap gap-2">{children}</div>
    </li>
  );
}

function Editor({
  draft,
  pages,
  directory,
  saving,
  onCancel,
  onSave,
}: {
  draft: Draft;
  pages: Page[];
  directory: Person[];
  saving: boolean;
  onCancel: () => void;
  onSave: (d: Draft) => void;
}) {
  const [d, setD] = useState(draft);
  const [query, setQuery] = useState("");
  // The chosen person's work, keyed by whose it is so a stale answer never shows.
  const [loaded, setLoaded] = useState<{ for: string; posts: PickablePost[] } | null>(null);
  const personID = d.person?.profileID;
  useEffect(() => {
    if (!personID) return;
    let live = true;
    postsFor(personID).then((posts) => live && setLoaded({ for: personID, posts }));
    return () => {
      live = false;
    };
  }, [personID]);
  const posts = loaded && loaded.for === personID ? loaded.posts : null;

  // The directory, narrowed to this page's role tags unless "everyone" is on.
  const [everyone, setEveryone] = useState(false);
  const tags = useMemo(() => pages.find((p) => p.slug === d.category)?.tags ?? [], [pages, d.category]);
  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    return directory.filter(
      (p) =>
        (everyone || (p.roles ?? []).some((r) => tags.includes(r))) &&
        (!q || p.name.toLowerCase().includes(q) || (p.roles ?? []).some((r) => r.toLowerCase().includes(q))),
    );
  }, [query, directory, everyone, tags]);

  function togglePost(id: string) {
    setD((cur) => ({
      ...cur,
      postIDs: cur.postIDs.includes(id) ? cur.postIDs.filter((x) => x !== id) : cur.postIDs.length >= 6 ? cur.postIDs : [...cur.postIDs, id],
    }));
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:p-10" onClick={onCancel}>
      <div className="w-full max-w-2xl space-y-5 rounded-2xl bg-background p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold">{d.applicationID ? "Feature applicant" : "Featured person"}</h2>
          <button className="text-muted hover:text-foreground" onClick={onCancel} aria-label="Close">
            ✕
          </button>
        </div>

        {d.application && (
          <div className="rounded-xl bg-surface p-3 text-sm">
            <p className="font-semibold">Their application</p>
            <p className="mt-1 line-clamp-4 whitespace-pre-line text-foreground/85">{d.application.message}</p>
          </div>
        )}

        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Page</span>
          <select
            value={d.category}
            onChange={(e) => setD({ ...d, category: e.target.value })}
            className="w-full rounded-xl border border-border bg-background p-2.5 text-sm"
          >
            {pages.map((p) => (
              <option key={p.slug} value={p.slug}>
                {p.label}
              </option>
            ))}
          </select>
        </label>

        <div>
          <span className="mb-1.5 block text-sm font-medium">Person</span>
          {d.person ? (
            <div className="flex items-center gap-3 rounded-xl border border-border p-3">
              <Avatar name={d.person.name} src={d.person.imageUrl} size="sm" />
              <span className="flex-1 font-semibold">{d.person.name}</span>
              <button className="text-sm text-muted hover:text-foreground" onClick={() => setD({ ...d, person: null, postIDs: [] })}>
                Change
              </button>
            </div>
          ) : (
            <>
              <p className="mb-2 text-xs text-muted">
                {everyone ? "Everyone in the directory" : `Profiles tagged ${tags.join(", ")}`}
              </p>
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={directory.length ? "Filter by name or tag" : "Profiles couldn't be loaded"}
                className="w-full rounded-xl border border-border bg-background p-2.5 text-sm outline-none focus:border-brand"
              />
              <label className="mt-2 flex items-center gap-2 text-xs text-muted">
                <input type="checkbox" checked={everyone} onChange={(e) => setEveryone(e.target.checked)} className="accent-[var(--brand)]" />
                Show profiles without these tags too
              </label>
              {d.application && !d.application.profileID && (
                <p className="mt-1.5 text-xs text-muted">This applicant&rsquo;s email isn&rsquo;t linked to an app account, so find their profile by name.</p>
              )}
              {matches.length === 0 ? (
                <p className="mt-3 text-sm text-muted">{query ? "No one matches." : "No profiles have these tags yet."}</p>
              ) : (
                <ul className="mt-2 max-h-72 divide-y divide-border overflow-y-auto rounded-xl border border-border">
                  {matches.map((p) => (
                    <li key={p.profileID}>
                      <button className="flex w-full items-center gap-3 p-2.5 text-left hover:bg-surface" onClick={() => setD({ ...d, person: p })}>
                        <Avatar name={p.name} src={p.imageUrl} size="sm" />
                        <span className="min-w-0 flex-1">
                          <span className="block text-sm font-medium">{p.name}</span>
                          {!!p.roles?.length && (
                            <span className="block truncate text-xs text-muted">
                              {p.roles.map((r, i) => (
                                <span key={r} className={tags.includes(r) ? "font-semibold text-brand" : ""}>
                                  {i > 0 && ", "}
                                  {r}
                                </span>
                              ))}
                            </span>
                          )}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
        </div>

        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Your blurb</span>
          <textarea
            value={d.blurb}
            onChange={(e) => setD({ ...d, blurb: e.target.value })}
            rows={4}
            maxLength={2000}
            placeholder="Why they're worth a look."
            className="w-full rounded-xl border border-border bg-background p-3 text-sm outline-none focus:border-brand"
          />
        </label>

        {d.person && (
          <div>
            <span className="mb-1.5 block text-sm font-medium">
              Work to show <span className="font-normal text-muted">(up to 6, in the order you pick)</span>
            </span>
            {posts === null ? (
              <p className="text-sm text-muted">Loading their work…</p>
            ) : posts.length === 0 ? (
              <p className="text-sm text-muted">No credited work found for this profile.</p>
            ) : (
              <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {posts.map((p) => {
                  const n = d.postIDs.indexOf(p.id);
                  return (
                    <li key={p.id}>
                      <button
                        type="button"
                        onClick={() => togglePost(p.id)}
                        className={`relative block w-full overflow-hidden rounded-xl text-left ring-2 transition ${n >= 0 ? "ring-brand" : "ring-transparent hover:ring-border"}`}
                      >
                        <div className="aspect-video bg-surface">
                          {p.thumbnailUrl && (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img src={p.thumbnailUrl} alt="" loading="lazy" className="h-full w-full object-cover" />
                          )}
                        </div>
                        <p className="line-clamp-1 p-2 text-xs font-medium">{p.title}</p>
                        {n >= 0 && (
                          <span className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-brand text-xs font-bold text-white">
                            {n + 1}
                          </span>
                        )}
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        )}

        <div className="flex justify-end gap-2 pt-2">
          <button className={quiet} onClick={onCancel}>
            Cancel
          </button>
          <button className={primary} disabled={saving || !d.person} onClick={() => onSave(d)}>
            {saving ? "Saving…" : d.applicationID ? "Feature them" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}

function Thumb({ post }: { post?: CatalogPost }) {
  const cat = post ? getCategory(post.category) : undefined;
  return (
    <div className="flex h-12 w-20 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-foreground/10">
      {post?.thumbnailUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={post.thumbnailUrl} alt="" loading="lazy" className="h-full w-full object-cover" />
      ) : (
        cat && <span className="text-xs text-muted">{cat.label}</span>
      )}
    </div>
  );
}

/** Choose a post (when adding) and write its note. */
function PickEditor({
  initial,
  title,
  catalog,
  picked,
  saving,
  onCancel,
  onSave,
}: {
  initial: { postID: string | null; note: string };
  /** Heading; defaults to adding or editing a Featured pick. */
  title?: string;
  catalog: CatalogPost[];
  picked: Set<string>;
  saving: boolean;
  onCancel: () => void;
  onSave: (postID: string, note: string) => void;
}) {
  const [postID, setPostID] = useState(initial.postID);
  const [note, setNote] = useState(initial.note);
  const [query, setQuery] = useState("");
  const adding = initial.postID === null;
  const chosen = catalog.find((p) => p.id === postID);
  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    return catalog.filter(
      (p) => !picked.has(p.id) && (!q || p.title.toLowerCase().includes(q) || p.creator.toLowerCase().includes(q)),
    );
  }, [query, catalog, picked]);

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:p-10" onClick={onCancel}>
      <div className="w-full max-w-2xl space-y-5 rounded-2xl bg-background p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold">{title ?? (adding ? "Add to Featured" : "Edit note")}</h2>
          <button className="text-muted hover:text-foreground" onClick={onCancel} aria-label="Close">
            ✕
          </button>
        </div>

        {chosen ? (
          <div className="flex items-center gap-3 rounded-xl border border-border p-3">
            <Thumb post={chosen} />
            <div className="min-w-0 flex-1">
              <p className="truncate font-semibold">{chosen.title}</p>
              <p className="truncate text-sm text-muted">{chosen.creator}</p>
            </div>
            {adding && (
              <button className="text-sm text-muted hover:text-foreground" onClick={() => setPostID(null)}>
                Change
              </button>
            )}
          </div>
        ) : (
          <div>
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter posts by title or artist"
              className="w-full rounded-xl border border-border bg-background p-2.5 text-sm outline-none focus:border-brand"
            />
            {matches.length === 0 ? (
              <p className="mt-3 text-sm text-muted">{catalog.length ? "No posts match." : "Posts couldn't be loaded."}</p>
            ) : (
              <ul className="mt-2 max-h-80 divide-y divide-border overflow-y-auto rounded-xl border border-border">
                {matches.map((p) => (
                  <li key={p.id}>
                    <button className="flex w-full items-center gap-3 p-2.5 text-left hover:bg-surface" onClick={() => setPostID(p.id)}>
                      <Thumb post={p} />
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-medium">{p.title}</span>
                        <span className="block truncate text-xs text-muted">
                          {p.creator} · {getCategory(p.category)?.label}
                        </span>
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}

        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">
            Note <span className="font-normal text-muted">(optional, shown under the post)</span>
          </span>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
            maxLength={500}
            placeholder="Why it's a pick."
            className="w-full rounded-xl border border-border bg-background p-3 text-sm outline-none focus:border-brand"
          />
        </label>

        <div className="flex justify-end gap-2">
          <button className={quiet} onClick={onCancel}>
            Cancel
          </button>
          <button className={primary} disabled={saving || !postID} onClick={() => postID && onSave(postID, note)}>
            {saving ? "Saving…" : adding ? "Add" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Name (and describe) a Featured collection. */
function CollectionEditor({
  initial,
  saving,
  onCancel,
  onSave,
}: {
  initial: { id?: string; title: string; description: string };
  saving: boolean;
  onCancel: () => void;
  onSave: (c: { title: string; description: string }) => void;
}) {
  const [title, setTitle] = useState(initial.title);
  const [description, setDescription] = useState(initial.description);
  const field = "w-full rounded-xl border border-border bg-background p-2.5 text-sm outline-none focus:border-brand";
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:p-10" onClick={onCancel}>
      <form
        className="w-full max-w-lg space-y-5 rounded-2xl bg-background p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        onSubmit={(e) => {
          e.preventDefault();
          if (title.trim()) onSave({ title: title.trim(), description: description.trim() });
        }}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold">{initial.id ? "Edit collection" : "New collection"}</h2>
          <button type="button" className="text-muted hover:text-foreground" onClick={onCancel} aria-label="Close">
            ✕
          </button>
        </div>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">Title</span>
          <input autoFocus value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} placeholder="Fall Showcase 2026" className={field} />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-sm font-medium">
            Description <span className="font-normal text-muted">(optional)</span>
          </span>
          <textarea value={description} maxLength={500} rows={2} onChange={(e) => setDescription(e.target.value)} className={field} />
        </label>
        <div className="flex justify-end gap-2">
          <button type="button" className={quiet} onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className={primary} disabled={saving || !title.trim()}>
            {saving ? "Saving…" : initial.id ? "Save" : "Create"}
          </button>
        </div>
      </form>
    </div>
  );
}

/** Pick several people from the directory and add them to one page in one go. */
function BulkAdder({
  page,
  directory,
  onPage,
  saving,
  onCancel,
  onSave,
}: {
  page: Page;
  directory: Person[];
  onPage: Set<string>;
  saving: boolean;
  onCancel: () => void;
  onSave: (people: Person[]) => void;
}) {
  const [query, setQuery] = useState("");
  const [everyone, setEveryone] = useState(false);
  // Kept in the order ticked, so that's the order they appear on the page.
  const [chosen, setChosen] = useState<Person[]>([]);
  const chosenIDs = useMemo(() => new Set(chosen.map((p) => p.profileID)), [chosen]);
  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    return directory.filter(
      (p) =>
        !onPage.has(p.profileID) &&
        (everyone || (p.roles ?? []).some((r) => page.tags.includes(r))) &&
        (!q || p.name.toLowerCase().includes(q) || (p.roles ?? []).some((r) => r.toLowerCase().includes(q))),
    );
  }, [query, directory, everyone, page.tags, onPage]);
  const allShownChosen = matches.length > 0 && matches.every((p) => chosenIDs.has(p.profileID));

  function toggle(p: Person) {
    setChosen((cur) => (cur.some((c) => c.profileID === p.profileID) ? cur.filter((c) => c.profileID !== p.profileID) : [...cur, p]));
  }
  function toggleAllShown() {
    setChosen((cur) =>
      allShownChosen
        ? cur.filter((c) => !matches.some((m) => m.profileID === c.profileID))
        : [...cur, ...matches.filter((m) => !cur.some((c) => c.profileID === m.profileID))],
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4 sm:p-10" onClick={onCancel}>
      <div className="w-full max-w-2xl space-y-4 rounded-2xl bg-background p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold">Add people to {page.label}</h2>
          <button className="text-muted hover:text-foreground" onClick={onCancel} aria-label="Close">
            ✕
          </button>
        </div>
        <p className="text-sm text-muted">Tick everyone you want. They&rsquo;re added without a blurb or posts; use Edit afterwards to fill those in.</p>

        {chosen.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {chosen.map((p) => (
              <button
                key={p.profileID}
                onClick={() => toggle(p)}
                className="flex items-center gap-1.5 rounded-full bg-brand/15 py-1 pl-1 pr-2.5 text-xs font-medium text-brand hover:bg-brand/25"
                aria-label={`Remove ${p.name}`}
              >
                <Avatar name={p.name} src={p.imageUrl} size="sm" />
                {p.name} ✕
              </button>
            ))}
          </div>
        )}

        <div>
          <p className="mb-2 text-xs text-muted">{everyone ? "Everyone in the directory" : `Profiles tagged ${page.tags.join(", ")}`}</p>
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={directory.length ? "Filter by name or tag" : "Profiles couldn't be loaded"}
            className="w-full rounded-xl border border-border bg-background p-2.5 text-sm outline-none focus:border-brand"
          />
          <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
            <label className="flex items-center gap-2 text-xs text-muted">
              <input type="checkbox" checked={everyone} onChange={(e) => setEveryone(e.target.checked)} className="accent-[var(--brand)]" />
              Show profiles without these tags too
            </label>
            {matches.length > 1 && (
              <button className="text-xs font-semibold text-brand hover:underline" onClick={toggleAllShown}>
                {allShownChosen ? "Unselect all shown" : `Select all shown (${matches.length})`}
              </button>
            )}
          </div>
          {matches.length === 0 ? (
            <p className="mt-3 text-sm text-muted">{query ? "No one matches." : "Everyone with these tags is already on this page."}</p>
          ) : (
            <ul className="mt-2 max-h-80 divide-y divide-border overflow-y-auto rounded-xl border border-border">
              {matches.map((p) => {
                const on = chosenIDs.has(p.profileID);
                return (
                  <li key={p.profileID}>
                    <label className={`flex w-full cursor-pointer items-center gap-3 p-2.5 hover:bg-surface ${on ? "bg-brand/5" : ""}`}>
                      <input type="checkbox" checked={on} onChange={() => toggle(p)} className="h-4 w-4 accent-[var(--brand)]" />
                      <Avatar name={p.name} src={p.imageUrl} size="sm" />
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm font-medium">{p.name}</span>
                        {!!p.roles?.length && <span className="block truncate text-xs text-muted">{p.roles.join(", ")}</span>}
                      </span>
                    </label>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button className={quiet} onClick={onCancel}>
            Cancel
          </button>
          <button className={primary} disabled={saving || chosen.length === 0} onClick={() => onSave(chosen)}>
            {saving ? "Adding…" : chosen.length === 0 ? "Add" : `Add ${chosen.length} ${chosen.length === 1 ? "person" : "people"}`}
          </button>
        </div>
      </div>
    </div>
  );
}
