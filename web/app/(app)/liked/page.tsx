import { Suspense } from "react";
import Link from "next/link";
import ComingSoon from "@/components/ComingSoon";
import ContentGrid from "@/components/ContentGrid";
import { currentAccount } from "@/lib/account";
import { isCloudKitConfigured } from "@/lib/cloudkit/client";
import { likedPostIDs } from "@/lib/cloudkit/likes";
import { feedPosts, findPost } from "@/lib/content";
import type { Post } from "@/lib/mockContent";

const PLACEHOLDER = <ComingSoon title="Liked" body="Posts you like will show up here once you're signed in." />;

export default function Liked() {
  return (
    <Suspense fallback={null}>
      <LikedPosts />
    </Suspense>
  );
}

type Loaded = { kind: "placeholder" } | { kind: "signin" } | { kind: "empty" } | { kind: "posts"; posts: Post[] };

/** Everything that can throw lives here, so the page itself never builds JSX inside a try. */
async function load(): Promise<Loaded> {
  // Anything unexpected (no keys, wrong keys, a missing record type) leaves the page as it was.
  if (!isCloudKitConfigured()) return { kind: "placeholder" };
  try {
    const current = await currentAccount();
    if (!current) return { kind: "signin" };
    const me = current.session.userRecordName;
    if (!me) return { kind: "placeholder" };

    const [ids, feed] = await Promise.all([likedPostIDs(me), feedPosts()]);
    const byID = new Map(feed.map((p) => [p.id.toUpperCase(), p]));
    // A liked festival-bound film isn't on the feed but is still reachable, so look it up.
    const posts = (await Promise.all(ids.map((id) => byID.get(id.toUpperCase()) ?? findPost(id)))).filter((p): p is Post => !!p);
    return posts.length ? { kind: "posts", posts } : { kind: "empty" };
  } catch (error) {
    console.error("[liked]", error instanceof Error ? error.message : error);
    return { kind: "placeholder" };
  }
}

async function LikedPosts() {
  const result = await load();
  if (result.kind === "placeholder") return PLACEHOLDER;
  if (result.kind === "empty") return <ComingSoon title="Liked" body="Nothing here yet. Tap Like on a post and it shows up here." />;
  if (result.kind === "signin") {
    return (
      <ComingSoon title="Liked" body="Sign in with your school email to see the posts you've liked.">
        <Link href="/signin" className="mt-4 inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          Sign in
        </Link>
      </ComingSoon>
    );
  }
  return (
    <div className="w-full">
      <h1 className="mt-4 text-3xl font-bold">Liked</h1>
      <div className="mt-5">
        <ContentGrid posts={result.posts} />
      </div>
    </div>
  );
}
