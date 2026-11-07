import Link from "next/link";
import { Suspense } from "react";
import StyleEditForm from "@/components/StyleEditForm";
import { creditedPosts, currentAccount } from "@/lib/account";
import { getCreativeProfile } from "@/lib/cloudkit/creative";
import { myStyle } from "@/lib/myStyle";
import { emptyDetails, suggestedStyle } from "@/lib/profileStyle";

/** Pick your base profile style and fill in what that style's profile shows. */
export default function EditStyle() {
  return (
    <Suspense fallback={<p className="py-20 text-center text-muted">Loading…</p>}>
      <Editor />
    </Suspense>
  );
}

async function Editor() {
  const current = await currentAccount();
  const user = current?.session.userRecordName;
  if (!current?.account || !user) {
    return (
      <div className="mx-auto mt-16 max-w-md space-y-4 rounded-2xl border border-border bg-surface p-10 text-center">
        <h1 className="text-2xl font-bold">Profile style</h1>
        <p className="text-muted">
          {!current
            ? "Sign in with your school email to choose your profile style."
            : "This email isn't linked to a Nexus account yet. Verify it in the Nexus app, then sign out and back in here."}
        </p>
        <Link href={current ? "/portfolio" : "/signin"} className="inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          {current ? "Back to profile" : "Sign in"}
        </Link>
      </div>
    );
  }

  const [profile, mine, posts] = await Promise.all([getCreativeProfile(user), myStyle(), creditedPosts(current.account)]);
  const reels = posts
    .filter((p) => p.category === "performance" || p.category === "film")
    .map((p) => ({ id: p.id, title: p.title, thumbnailUrl: p.thumbnailUrl }));

  return (
    <StyleEditForm
      initialStyle={profile?.style ?? mine.style ?? suggestedStyle(current.account.roles) ?? null}
      initial={profile?.details ?? emptyDetails()}
      headshotUrl={profile?.headshotUrl}
      reels={reels}
    />
  );
}
