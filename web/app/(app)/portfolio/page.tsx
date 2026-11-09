import Link from "next/link";
import { Suspense } from "react";
import ProfileView, { ProfileSkeleton } from "@/components/ProfileView";
import StyledProfile from "@/components/StyledProfile";
import { getCreativeProfile } from "@/lib/cloudkit/creative";
import { discoverItems } from "@/lib/content";
import type { DiscoverItem, NexusEvent } from "@/lib/discoverContent";
import SignOutButton from "@/components/SignOutButton";
import { creditedPosts, currentAccount } from "@/lib/account";

export default function Portfolio() {
  return (
    <Suspense fallback={<ProfileSkeleton />}>
      <Profile />
    </Suspense>
  );
}

async function Profile() {
  const current = await currentAccount();

  if (!current) {
    return (
      <Notice title="Your profile" body="Sign in with your school email to see your profile and work.">
        <Link href="/signin" className="rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          Sign in
        </Link>
      </Notice>
    );
  }

  const { session, account } = current;
  if (!account) {
    return (
      <Notice
        title={`Signed in as ${session.email}`}
        body="This email isn't linked to a Nexus account yet. Verify it in the Nexus app, then sign out and back in here to see your profile."
      >
        <SignOutButton />
      </Notice>
    );
  }

  const [posts, creative, items] = await Promise.all([
    creditedPosts(account),
    session.userRecordName ? getCreativeProfile(session.userRecordName) : Promise.resolve(null),
    discoverItems().catch((): DiscoverItem[] => []),
  ]);
  const events = items.filter((i): i is NexusEvent => i.kind === "event");
  return (
    <ProfileView
      styled={<StyledProfile account={account} posts={posts} creative={creative} events={events} isOwn />}
      account={account}
      posts={posts}
      displayName={session.email}
      schoolFallback={session.schoolName}
      actions={
        <div className="flex items-center gap-2">
          <Link href="/portfolio/edit" className="rounded-full border border-border px-4 py-1.5 text-sm font-medium transition hover:bg-surface">
            Edit profile
          </Link>
          <Link href="/portfolio/style" className="rounded-full border border-border px-4 py-1.5 text-sm font-medium transition hover:bg-surface">
            Profile style
          </Link>
          <SignOutButton />
        </div>
      }
      emptyText="No credited work yet. Posts you’re credited on in the app show up here."
    />
  );
}

function Notice({ title, body, children }: { title: string; body: string; children: React.ReactNode }) {
  return (
    <div className="mx-auto mt-16 max-w-md space-y-4 rounded-2xl border border-border bg-surface p-10 text-center">
      <h1 className="break-words text-2xl font-bold">{title}</h1>
      <p className="text-muted">{body}</p>
      <div className="flex justify-center">{children}</div>
    </div>
  );
}
