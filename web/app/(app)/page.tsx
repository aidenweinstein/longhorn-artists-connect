import { connection } from "next/server";
import ContentGrid from "@/components/ContentGrid";
import { feedPosts } from "@/lib/content";
import { filterPosts } from "@/lib/filterPosts";
import { mixFeed } from "@/lib/mixFeed";
import { myStyle } from "@/lib/myStyle";
import { recommend } from "@/lib/profileStyle";

// The feed is filtered per request by ?category and ?q, so this route blocks until it renders.
export const instant = false;

export default async function Home(props: PageProps<"/">) {
  const params = await props.searchParams;
  // A fresh shuffle on every visit, so the order is decided per request.
  await connection();
  const [posts, { style }] = await Promise.all([feedPosts(), myStyle().catch(() => ({ style: null }))]);
  const mixed = mixFeed(filterPosts(params, posts));
  // On the unfiltered feed, lead with the kind of work the viewer's profile style is about.
  return <ContentGrid posts={style && !params.category ? recommend(style, mixed) : mixed} />;
}
