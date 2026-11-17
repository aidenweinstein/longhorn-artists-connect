import Link from "next/link";
import DraftsList from "@/components/share/DraftsList";

/**
 * Share's Drafts page, opened from the Drafts button on the page bar. Same layout as the
 * app's DraftsView: a list of saved drafts, or "No drafts yet". Drafts are saved from a
 * Share form's Save draft button and kept in this browser (lib/shareDrafts.ts).
 */
export default function Drafts() {
  return (
    <div className="w-full space-y-6 px-3 pb-24 pt-3 sm:px-6 sm:pt-5 lg:px-10">
      <Link href="/share" className="text-sm text-muted hover:text-foreground">
        ← Share
      </Link>
      <h1 className="text-3xl font-bold">Drafts</h1>
      <DraftsList />
    </div>
  );
}
