import DiscoverProjects from "./projects/page";

// Filtered per request by ?q, so this route blocks until it renders.
export const instant = false;

/** Discover opens on Projects: the same grid as /discover/projects. */
export default function Discover(props: PageProps<"/discover">) {
  return <DiscoverProjects {...props} />;
}
