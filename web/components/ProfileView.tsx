import Avatar from "./Avatar";
import WorkStatusPill from "./WorkStatusPill";
import WorkStatusPicker from "./WorkStatusPicker";
import PortfolioGrid from "./PortfolioGrid";
import CollaboratorsStat from "./CollaboratorsStat";
import { collaboratorList, type Collaborators } from "@/lib/account";
import type { Account } from "@/lib/cloudkit/content";
import { toCard } from "@/lib/feedCard";
import type { Post } from "@/lib/mockContent";
import { sortByOrder } from "@/lib/portfolioLayout";

/** A person's portfolio: header, stats, links and credited work. Used for your own page and everyone else's. */
export default function ProfileView({
  account,
  posts,
  displayName,
  schoolFallback,
  actions,
  editableStatus = false,
  note,
  emptyText,
  styled,
  info,
  collaborators,
  profileActions,
  canEditGrid,
}: {
  account: Account;
  posts: Post[];
  displayName?: string;
  schoolFallback?: string;
  /** Buttons beside the name, e.g. Sign out on your own page. */
  actions?: React.ReactNode;
  /** Your own page: the status pill opens a menu to change it. */
  editableStatus?: boolean;
  /** A short line under the name, e.g. for someone not on Nexus yet. */
  note?: string;
  emptyText: string;
  /** Reel and resume, filmography, songs and shows, under the Work grid: StyledProfile part="lists". */
  styled?: React.ReactNode;
  /** Actor, Filmmaker and Musician cards, beside the details: StyledProfile part="info". */
  info?: React.ReactNode;
  /** Who they've worked with, checked against Nexus accounts (see collaboratorsFor). */
  collaborators?: Collaborators;
  /** Connect and Message, shown under the person's info on someone else's page. */
  profileActions?: React.ReactNode;
  /** Your own portfolio: shows Edit grid, to reorder the Work grid and resize its posts. */
  canEditGrid?: boolean;
}) {
  const stats: [string, number][] = [
    ["Projects", posts.length],
    // Connects are requested and accepted in the app; none exist yet to count.
    ["Connects", 0],
  ];
  // Without a directory check, anyone linked to a profile counts as on Nexus.
  const collabs = collaborators ?? collaboratorList(posts, account);
  const school = account.school || schoolFallback;

  return (
    <div className="mx-auto max-w-[1500px]">
      <div className="flex flex-col gap-8 lg:flex-row lg:items-start">
      {/* Only as wide as its content (up to max-w-3xl), so the cards beside it start right after it instead of at the far right. */}
      <section className="flex min-w-0 flex-col gap-6 sm:flex-row sm:items-start lg:max-w-3xl">
        <Avatar name={account.name} src={account.imageUrl} size="xl" />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center justify-between gap-3">
            {/* Name with Projects / Connects / Collabs to its right */}
            <div className="flex flex-wrap items-center gap-x-8 gap-y-2">
              <h1 className="text-3xl font-bold leading-tight">{account.name || displayName}</h1>
              <dl className="flex gap-6">
                {stats.map(([label, value]) => (
                  <div key={label} className="flex flex-col-reverse items-center">
                    <dt className="text-xs text-muted">{label}</dt>
                    <dd className="text-xl font-bold leading-tight tabular-nums">{value}</dd>
                  </div>
                ))}
                <div>
                  <dt className="sr-only">Collabs</dt>
                  <dd>
                    <CollaboratorsStat label="Collabs" collaborators={collabs} />
                  </dd>
                </div>
              </dl>
            </div>
            {actions}
          </div>
          {editableStatus ? (
            <WorkStatusPicker status={account.workStatus} className="mt-2" />
          ) : (
            <WorkStatusPill status={account.workStatus} className="mt-2" />
          )}
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

          {profileActions}
        </div>
      </section>
      {/* Actor, Filmmaker and Musician cards: right after the details on a wide window, under them on a narrow one. Only as wide as their text. */}
      {info && <aside className="w-fit max-w-full shrink-0 empty:hidden lg:max-w-md">{info}</aside>}
      </div>

      <hr className="my-8 border-border" />

      {posts.length > 0 ? (
        // In the person's own order and tile sizes (UserProfile.portfolioOrder / portfolioLayout).
        <PortfolioGrid posts={sortByOrder(posts, account.portfolioOrder).map(toCard)} sizes={account.portfolioLayout} editable={canEditGrid} />
      ) : <p className="py-12 text-center text-muted">{emptyText}</p>}

      {/* Resume, filmography, songs: under the grid. */}
      {styled && <div className="mt-12 space-y-12 border-t border-border pt-8 empty:hidden">{styled}</div>}
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
