import Link from "next/link";
import { notFound } from "next/navigation";
import ApplyForm from "@/components/ApplyForm";
import { currentAccount } from "@/lib/account";
import { PEOPLE_PAGES, peoplePage } from "@/lib/featured";

export const instant = false;

export function generateStaticParams() {
  return PEOPLE_PAGES.map((p) => ({ category: p.slug }));
}

export default async function Apply(props: PageProps<"/people/[category]/apply">) {
  const { category } = await props.params;
  const page = peoplePage(category);
  if (!page) notFound();
  const current = await currentAccount();

  return (
    <div className="mx-auto max-w-xl">
      <Link href={`/people/${page.slug}`} className="text-sm text-muted hover:text-foreground">
        ← {page.label}
      </Link>
      <h1 className="mt-2 text-3xl font-bold">Apply to be featured</h1>
      <p className="mt-2 text-muted">
        Tell us about your work as a {page.singular}. Everyone on this page is picked by hand, and we read every application.
      </p>

      {!current ? (
        <div className="mt-8 rounded-2xl bg-surface p-6 text-center">
          <p className="text-muted">Sign in with your school email to apply.</p>
          <Link href="/signin" className="mt-4 inline-block rounded-full bg-brand px-5 py-2 text-sm font-semibold text-white hover:brightness-110">
            Sign in
          </Link>
        </div>
      ) : (
        <>
          {!current.account && (
            <p className="mt-6 rounded-xl border border-border p-4 text-sm text-muted">
              Your email isn&rsquo;t linked to a Nexus account yet. You can still apply, but verifying it in the Nexus app first
              lets us show your profile and work.
            </p>
          )}
          <ApplyForm category={page.slug} defaultName={current.account?.name ?? ""} email={current.session.email} />
        </>
      )}
    </div>
  );
}
