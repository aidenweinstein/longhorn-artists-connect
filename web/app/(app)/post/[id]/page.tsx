import { allPostIDs } from "@/lib/content";
import PostView from "./PostView";

export async function generateStaticParams() {
  return (await allPostIDs()).map((id) => ({ id }));
}

export default async function PostPage(props: PageProps<"/post/[id]">) {
  const { id } = await props.params;
  return <PostView id={id} />;
}
