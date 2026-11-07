import Link from "next/link";
import { Suspense } from "react";
import ProfileEditForm from "@/components/ProfileEditForm";
import { currentAccount } from "@/lib/account";
import { getProfileFields } from "@/lib/cloudkit/content";

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
              ? "This email isn't linked to a Nexus account yet. Verify it in the Nexus app, then sign out and back in here."
              : "Your profile couldn't be loaded right now. Try again in a moment."}
        </p>
        <Link href={current ? "/portfolio" : "/signin"} className="inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
          {current ? "Back to profile" : "Sign in"}
        </Link>
      </div>
    );
  }

  return <ProfileEditForm initial={fields} imageUrl={current.account.imageUrl} school={current.account.school || current.session.schoolName} />;
}
