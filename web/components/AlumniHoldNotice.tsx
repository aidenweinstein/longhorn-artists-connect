import { currentSession } from "@/lib/account";
import { ALUMNI_WAITING, isPendingAlum } from "@/lib/alumni";

/** Tells a waiting alum why they can't post yet. Nothing for anyone else. Render inside <Suspense>. */
export default async function AlumniHoldNotice({ className = "" }: { className?: string }) {
  if (!(await isPendingAlum(await currentSession()))) return null;
  return (
    <div role="status" className={`rounded-2xl border border-border bg-surface px-5 py-4 text-sm ${className}`}>
      <p className="font-semibold">Waiting for approval</p>
      <p className="mt-1 text-muted">{ALUMNI_WAITING}</p>
    </div>
  );
}
