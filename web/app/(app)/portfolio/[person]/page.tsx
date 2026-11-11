import { Suspense } from "react";
import { notFound } from "next/navigation";
import ProfileView, { ProfileSkeleton } from "@/components/ProfileView";
import StyledProfile from "@/components/StyledProfile";
import { getCreativeProfile } from "@/lib/cloudkit/creative";
import { discoverItems } from "@/lib/content";
import type { DiscoverItem, NexusEvent } from "@/lib/discoverContent";
import SignOutButton from "@/components/SignOutButton";
import ProfileActions from "@/components/ProfileActions";
import { connectionState } from "@/lib/cloudkit/connections";
import { collaboratorsFor, creditedPosts, currentAccount, personAccount } from "@/lib/account";
import { sampleAccount, sampleById, sampleCreative } from "@/lib/sampleProfiles";

/** Anyone's portfolio, opened by clicking their name anywhere on the site. */
export default function PersonPortfolio(props: PageProps<"/portfolio/[person]">) {
  return (
    <Suspense fallback={<ProfileSkeleton />}>
      <Person params={props.params} />
    </Suspense>
  );
}

async function Person({ params }: { params: PageProps<"/portfolio/[person]">["params"] }) {
  const { person } = await params;
  const id = decodeURIComponent(person);

  // A sample actor from lib/sampleProfiles.ts, shown fully filled out.
  const sample = sampleById(id);
  const sampleStyle = sample && sampleCreative(sample);
  if (sample && sampleStyle) {
    const account = sampleAccount(sample);
    return (
      <ProfileView
        styled={<StyledProfile account={account} posts={[]} creative={sampleStyle} events={[]} />}
        account={account}
        posts={[]}
        note="Sample profile. Not a real person."
        emptyText="Samples have no posted work."
      />
    );
  }

  const [account, current] = await Promise.all([personAccount(id), currentAccount()]);
  if (!account) notFound();

  const linked = account.profileID !== "";
  const isMe = linked && current?.account?.profileID === account.profileID;
  const [posts, creative, items] = await Promise.all([
    creditedPosts(account),
    linked ? getCreativeProfile(account.profileID) : Promise.resolve(null),
    discoverItems().catch((): DiscoverItem[] => []),
  ]);
  const events = items.filter((i): i is NexusEvent => i.kind === "event");
  const collaborators = await collaboratorsFor(posts, account);

  // Connect and Message only between two real Nexus accounts, never on your own page.
  const me = current?.account ? current.session.userRecordName : undefined;
  const canInteract = linked && !isMe && !!me;
  const connection = canInteract && me ? await connectionState(me, account.profileID) : "none";

  return (
    <ProfileView
      collaborators={collaborators}
      styled={<StyledProfile account={account} posts={posts} creative={creative} events={events} isOwn={isMe} />}
      account={account}
      posts={posts}
      actions={isMe ? <SignOutButton /> : undefined}
      profileActions={canInteract ? <ProfileActions profileID={account.profileID} name={account.name} initialState={connection} /> : undefined}
      note={linked ? undefined : "Credited on Nexus, but not linked to a Nexus profile yet."}
      emptyText={`No credited work from ${account.name.split(" ")[0] || "them"} yet.`}
    />
  );
}
