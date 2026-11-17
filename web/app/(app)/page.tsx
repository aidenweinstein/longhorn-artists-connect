import { Suspense } from "react";
import { connection } from "next/server";
import { FeedSkeleton } from "@/components/ContentGrid";
import FeedGrid from "@/components/FeedGrid";
import { feedPage } from "@/lib/feedPage";
import { newFeedSeed } from "@/lib/mixFeed";

// The page itself is just a boundary, so the top bar, sidebar and a placeholder feed
// show at once (and come with the prefetch when you click Home); the real feed
// streams in behind them.
export default function Home(props: PageProps<"/">) {
  return (
    <Suspense fallback={<FeedSkeleton />}>
      <Feed searchParams={props.searchParams} />
    </Suspense>
  );
}

async function Feed({ searchParams }: { searchParams: PageProps<"/">["searchParams"] }) {
  const params = await searchParams;
  // A fresh shuffle on every visit, so the order is decided per request.
  await connection();
  const seed = newFeedSeed();
  const category = typeof params.category === "string" ? params.category : undefined;
  const q = typeof params.q === "string" ? params.q : undefined;
  // Only the first cards come with the page; FeedGrid fetches the rest as you scroll.
  const { cards, hasMore } = await feedPage({ category, q }, seed, 0);
  // Keyed by the shuffle, so a new filter or search starts a fresh list.
  return <FeedGrid key={seed} initial={cards} hasMore={hasMore} seed={seed} category={category} q={q} />;
}
