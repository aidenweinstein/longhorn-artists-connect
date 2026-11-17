import Link from "next/link";
import { Suspense } from "react";
import ProfileEditForm from "@/components/ProfileEditForm";
import { creditedPosts, currentAccount } from "@/lib/account";
import { getProfileFields } from "@/lib/cloudkit/content";
import { getCreativeProfile } from "@/lib/cloudkit/creative";
import { emptyDetails } from "@/lib/profileStyle";

export default function EditProfile() {
  return (
    <Suspense fallback={<p className="py-20 text-center text-muted">Loading your profile…</p>}>
      <Editor />
    </Suspense>
  );
}

async function Editor() {
  const current = await currentAccount();
  const userRecordName = current?.session.userRecordName;
  const fields = userRecordName && current?.account ? await getProfileFields(userRecordName).catch(() => null) : null;

  if (!current || !current.account || !fields) {
    return (
      <div className="mx-auto mt-16 max-w-md space-y-4 rounded-2xl border border-border bg-surface p-10 text-center">
        <h1 className="text-2xl font-bold">Edit profile</h1>
        <p className="text-muted">
          {!current
            ? "Sign in with your school email to edit your profile."
            : !current.account
              ? "This email doesn't have a Nexus account yet. Create one first, then you can edit your profile."
              : "Your profile couldn't be loaded right now. Try again in a moment."}
        </p>
        <Link
          href={!current ? "/signin" : !current.account && !userRecordName ? "/signup/finish" : "/portfolio"}
          className="inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110"
        >
          {!current ? "Sign in" : !current.account && !userRecordName ? "Create your account" : "Back to profile"}
        </Link>
      </div>
    );
  }

  const [creative, posts] = await Promise.all([getCreativeProfile(userRecordName!), creditedPosts(current.account).catch(() => [])]);
  const reels = posts.filter((p) => p.category === "performance" || p.category === "film").map((p) => ({ id: p.id, title: p.title }));

  return (
    <ProfileEditForm
      initial={fields}
      imageUrl={current.account.imageUrl}
      school={current.account.school || current.session.schoolName}
      creative={creative?.details ?? emptyDetails()}
      headshotUrl={creative?.headshotUrl}
      reels={reels}
    />
  );
}
