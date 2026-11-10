import Avatar from "./Avatar";
import WorkStatusPill from "./WorkStatusPill";
import ContentGrid from "./ContentGrid";
import { collaborators } from "@/lib/account";
import type { Account } from "@/lib/cloudkit/content";
import type { Post } from "@/lib/mockContent";

/** A person's portfolio: header, stats, links and credited work. Used for your own page and everyone else's. */
export default function ProfileView({
  account,
  posts,
  displayName,
  schoolFallback,
  actions,
  note,
  emptyText,
  styled,
}: {
  account: Account;
  posts: Post[];
  displayName?: string;
  schoolFallback?: string;
  /** Buttons beside the name, e.g. Sign out on your own page. */
  actions?: React.ReactNode;
  /** A short line under the name, e.g. for someone not on Nexus yet. */
  note?: string;
  emptyText: string;
  /** The profile-style section (actor resume, filmography, discography): see StyledProfile. */
  styled?: React.ReactNode;
}) {
  const stats: [string, number][] = [
    ["Credits", posts.length],
    // Connects are requested and accepted in the app; none exist yet to count.
    ["Connects", 0],
    ["Collabs", collaborators(posts, account)],
  ];
  const school = account.school || schoolFallback;

  return (
    <div className="mx-auto max-w-[1500px]">
      <section className="flex flex-col gap-6 sm:flex-row sm:items-start">
        <Avatar name={account.name} src={account.imageUrl} size="xl" />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center justify-between gap-3">
            {/* Name with Credits / Connects / Collabs to its right */}
            <div className="flex flex-wrap items-center gap-x-8 gap-y-2">
              <h1 className="text-3xl font-bold leading-tight">{account.name || displayName}</h1>
              <dl className="flex gap-6">
                {stats.map(([label, value]) => (
                  <div key={label} className="flex flex-col-reverse items-center">
                    <dt className="text-xs text-muted">{label}</dt>
                    <dd className="text-xl font-bold leading-tight tabular-nums">{value}</dd>
                  </div>
                ))}
              </dl>
            </div>
            {actions}
          </div>
          <WorkStatusPill status={account.workStatus} className="mt-2" />
          {account.academicLine && <p className="mt-1 text-muted">{account.academicLine}</p>}
          {school && <p className="text-sm text-muted">{school}</p>}
          {note && <p className="mt-1 text-sm text-muted">{note}</p>}

          {account.roles.length > 0 && (
            <div className="mt-3 flex flex-wrap gap-2">
              {account.roles.map((role) => (
                <span key={role} className="rounded-full bg-brand/15 px-3 py-1 text-sm font-medium text-brand">
                  {role}
                </span>
              ))}
            </div>
          )}


          {account.bio && <p className="mt-4 max-w-2xl whitespace-pre-line leading-relaxed text-foreground/85">{account.bio}</p>}

          {(account.instagram || account.website) && (
            <div className="mt-3 flex flex-wrap gap-2">
              {account.instagram && (
                <a
                  href={`https://instagram.com/${account.instagram}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-full bg-foreground/10 px-3.5 py-1.5 text-sm font-medium hover:bg-foreground/20"
                >
                  @{account.instagram}
                </a>
              )}
              {account.website && (
                <a
                  href={/^https?:\/\//.test(account.website) ? account.website : `https://${account.website}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-full bg-foreground/10 px-3.5 py-1.5 text-sm font-medium hover:bg-foreground/20"
                >
                  {account.website.replace(/^https?:\/\//, "").replace(/\/$/, "")}
                </a>
              )}
            </div>
          )}
        </div>
      </section>

      {styled}

      <hr className="my-8 border-border" />

      <h2 className="mb-5 text-lg font-semibold">Work</h2>
      {posts.length > 0 ? <ContentGrid posts={posts} /> : <p className="py-12 text-center text-muted">{emptyText}</p>}
    </div>
  );
}

export function ProfileSkeleton() {
  return (
    <div aria-hidden className="mx-auto flex max-w-[1500px] animate-pulse gap-6">
      <span className="h-28 w-28 shrink-0 rounded-full bg-surface" />
      <div className="flex-1 space-y-3 pt-2">
        <span className="block h-8 w-64 rounded bg-surface" />
        <span className="block h-4 w-48 rounded bg-surface" />
        <span className="block h-4 w-80 rounded bg-surface" />
      </div>
    </div>
  );
}
