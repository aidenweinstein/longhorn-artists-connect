import { Suspense } from "react";
import { notFound } from "next/navigation";
import ProfileView, { ProfileSkeleton } from "@/components/ProfileView";
import StyledProfile from "@/components/StyledProfile";
import { getCreativeProfile } from "@/lib/cloudkit/creative";
import { discoverItems } from "@/lib/content";
import type { DiscoverItem, NexusEvent } from "@/lib/discoverContent";
import ProfileActionButtons from "@/components/ProfileActionButtons";
import { connectionCount, connectionState, type ConnectionState } from "@/lib/cloudkit/connections";
import SignOutButton from "@/components/SignOutButton";
import { creditedPosts, currentAccount, personAccount } from "@/lib/account";
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
  const [posts, creative, items, connections] = await Promise.all([
    creditedPosts(account),
    linked ? getCreativeProfile(account.profileID) : Promise.resolve(null),
    discoverItems().catch((): DiscoverItem[] => []),
    linked ? connectionCount(account.profileID) : Promise.resolve(undefined),
  ]);
  const events = items.filter((i): i is NexusEvent => i.kind === "event");

  // Connect and Message, for someone else's linked profile when the visitor has a Nexus account.
  const myID = current?.session.userRecordName;
  let buttons: React.ReactNode;
  if (linked && !isMe && myID && current?.account) {
    const state = await connectionState(myID, account.profileID).catch((): ConnectionState => "none");
    buttons = <ProfileActionButtons profileID={account.profileID} name={account.name} state={state} />;
  }

  return (
    <ProfileView
      styled={<StyledProfile account={account} posts={posts} creative={creative} events={events} isOwn={isMe} />}
      account={account}
      posts={posts}
      connections={connections}
      actions={isMe ? <SignOutButton /> : buttons}
      note={linked ? undefined : "Credited on Nexus, but not linked to a Nexus profile yet."}
      emptyText={`No credited work from ${account.name.split(" ")[0] || "them"} yet.`}
    />
  );
}
