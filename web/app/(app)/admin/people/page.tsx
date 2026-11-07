import { notFound } from "next/navigation";
import AdminPeople, { type AdminFeature } from "@/components/AdminPeople";
import { currentSession, personAccount } from "@/lib/account";
import { isCloudKitConfigured, profileDirectory } from "@/lib/cloudkit/content";
import { PEOPLE_PAGES, callPeople, featuredCollections, featuresFor, isAdmin, staffPicks, type Application } from "@/lib/featured";
import { feedPosts } from "@/lib/content";

// Admin-only, and always current.
export const instant = false;

export default async function AdminPeoplePage() {
  // Non-admins get a plain 404, so the page's existence isn't advertised.
  if (!isAdmin(await currentSession())) notFound();

  const [applications, declined, lists, directory, picks, posts, collections] = await Promise.all([
    callPeople<{ applications: Application[] }>("admin/applications", { status: "pending" }).then((r) => r.applications).catch(() => null),
    callPeople<{ applications: Application[] }>("admin/applications", { status: "declined" }).then((r) => r.applications).catch(() => []),
    Promise.all(PEOPLE_PAGES.map((p) => featuresFor(p.slug))),
    isCloudKitConfigured() ? profileDirectory().catch(() => []) : Promise.resolve([]),
    staffPicks(),
    feedPosts().catch(() => []),
    featuredCollections(),
  ]);
  // Every post in the feed, to choose staff picks from.
  const catalog = posts.map((p) => ({ id: p.id, title: p.title, creator: p.creator, thumbnailUrl: p.thumbnailUrl, category: p.category }));

  // Current photos for everyone featured.
  const features: Record<string, AdminFeature[]> = {};
  await Promise.all(
    PEOPLE_PAGES.map(async (p, i) => {
      features[p.slug] = await Promise.all(
        lists[i].map(async (f) => {
          const account = await personAccount(f.profileID).catch(() => null);
          return { ...f, name: account?.name || f.name, imageUrl: account?.imageUrl };
        }),
      );
    }),
  );

  return (
    <AdminPeople
      pages={PEOPLE_PAGES.map((p) => ({ slug: p.slug, label: p.label, tags: [...p.tags] }))}
      applications={applications}
      declined={declined}
      features={features}
      picks={picks}
      collections={collections}
      catalog={catalog}
      directory={directory.map((d) => ({ profileID: d.id, name: d.name, imageUrl: d.imageUrl, roles: d.roles }))}
    />
  );
}
