import Link from "next/link";
import { notFound } from "next/navigation";
import ProfileView from "@/components/ProfileView";
import { PEOPLE_PAGES, peoplePage } from "@/lib/featured";
import { samplePortfolio } from "@/lib/samplePortfolios";

export function generateStaticParams() {
  return PEOPLE_PAGES.map((p) => ({ category: p.slug }));
}

/** What a full portfolio looks like for this kind of artist. Placeholder content from lib/samplePortfolios.ts. */
export default async function SamplePortfolioPage(props: PageProps<"/people/[category]/sample">) {
  const { category } = await props.params;
  const page = peoplePage(category);
  if (!page) notFound();
  const { account, posts } = samplePortfolio(page.slug);

  return (
    <div>
      <div className="mx-auto mb-6 flex max-w-[1500px] flex-wrap items-center justify-between gap-3 rounded-xl border border-dashed border-brand/50 bg-brand/5 px-4 py-3 text-sm">
        <p>
          <span className="font-semibold text-brand">Sample portfolio.</span>{" "}
          <span className="text-muted">This is how a {page.singular}&apos;s portfolio looks with a lot of work on it. Nothing here is real.</span>
        </p>
        <Link href={`/people/${page.slug}`} className="font-semibold hover:underline">
          ← Back to {page.label}
        </Link>
      </div>
      <ProfileView account={account} posts={posts} emptyText="" />
    </div>
  );
}
