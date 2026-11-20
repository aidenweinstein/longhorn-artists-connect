import Link from "next/link";
import { notFound } from "next/navigation";
import AdminAlumni, { type AlumRow } from "@/components/AdminAlumni";
import { currentSession } from "@/lib/account";
import { getAccount, isCloudKitConfigured } from "@/lib/cloudkit/content";
import { isAdmin } from "@/lib/featured";
import { callAlumni, type PendingAlum } from "@/lib/alumniReview";

// Admin-only, and always current.
export const instant = false;

/** Alumni waiting for approval: they can only look around until approved here. */
export default async function AdminAlumniPage() {
  // Non-admins get a plain 404, so the page's existence isn't advertised.
  if (!isAdmin(await currentSession())) notFound();

  let pending: PendingAlum[] | null = null;
  let error: string | null = null;
  try {
    pending = (await callAlumni<{ alumni: PendingAlum[] }>("pending", {})).alumni;
  } catch (e) {
    error = e instanceof Error ? e.message : "Couldn't load the list.";
  }

  // Their profiles, for the name, picture and class.
  const rows: AlumRow[] = await Promise.all(
    (pending ?? []).map(async (alum) => {
      const account = isCloudKitConfigured() ? await getAccount(alum.userRecordName).catch(() => null) : null;
      return {
        ...alum,
        name: account?.name || "(no profile yet)",
        imageUrl: account?.imageUrl,
        profileID: account?.profileID,
        line: account?.academicLine || "",
      };
    }),
  );

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <header>
        <h1 className="text-3xl font-bold">Alumni</h1>
        <p className="mt-1 text-muted">
          Alumni sign up with any email, so check each one is who they say before approving. Until then they can only
          look around: no posting, connecting or messaging.{" "}
          <Link href="/admin/people" className="text-brand hover:underline">Manage</Link>
        </p>
      </header>
      {error ? (
        <p className="rounded-xl bg-red-500/10 p-3 text-sm text-red-500">{error}</p>
      ) : (
        <AdminAlumni rows={rows} />
      )}
    </div>
  );
}
