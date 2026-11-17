import Link from "next/link";
import { Suspense } from "react";
import { FeedSkeleton } from "@/components/ContentGrid";
import PostGrid from "@/components/PostGrid";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured, queryWhere } from "@/lib/cloudkit/client";
import { feedPosts } from "@/lib/content";

export default function Liked() {
  return (
    <Suspense fallback={<FeedSkeleton />}>
      <LikedPosts />
    </Suspense>
  );
}

/** Every post the signed-in account has liked, here or in the app, newest like first. */
async function LikedPosts() {
  const current = await currentAccount();
  if (!current) {
    return (
      <Notice body="Sign in with your school email to see the posts you've liked.">
        <Link href="/signin" className="rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          Sign in
        </Link>
      </Notice>
    );
  }
  const user = current.session.userRecordName;
  if (!user) {
    return <Notice body="This email isn't linked to a Nexus account yet, so there are no likes to show." />;
  }
  if (!isCloudKitConfigured()) return <Empty />;

  let likes;
  try {
    likes = await queryWhere("PostLike", "userID", user, ["postID", "createdDate"]);
  } catch (error) {
    console.error("[liked]", error instanceof Error ? error.message : error);
    return <Notice body="Couldn't load your liked posts. Try again in a moment." />;
  }
  const when = (r: (typeof likes)[number]) => Number(r.fields.createdDate?.value ?? r.created?.timestamp ?? 0);
  // The app stores post IDs uppercase; match either way.
  const byID = new Map((await feedPosts()).map((p) => [p.id.toUpperCase(), p]));
  const posts = [...likes]
    .sort((a, b) => when(b) - when(a))
    .map((r) => byID.get(String(r.fields.postID?.value ?? "").toUpperCase()))
    .filter((p) => p !== undefined);

  return posts.length ? <PostGrid posts={posts} /> : <Empty />;
}

function Empty() {
  return <p className="py-20 text-center text-muted">Posts you like will show up here.</p>;
}

function Notice({ body, children }: { body: string; children?: React.ReactNode }) {
  return (
    <div className="mx-auto mt-16 max-w-md space-y-4 rounded-2xl border border-border bg-surface p-10 text-center">
      <p className="text-muted">{body}</p>
      {children && <div className="flex justify-center">{children}</div>}
    </div>
  );
}
