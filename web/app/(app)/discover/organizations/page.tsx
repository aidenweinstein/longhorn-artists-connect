import Link from "next/link";
import GroupsToggle from "@/components/GroupsToggle";
import { organizations } from "@/lib/content";

// Reads live data per request, so this route blocks until it renders.
export const instant = false;

/** Groups' Organizations list: every student organization, in the app's order and colors. Each card opens the org's page. */
export default async function Organizations() {
  const orgs = await organizations();
  return (
    <div>
      <GroupsToggle on="organizations" />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {orgs.map((o) => (
          <Link
            key={o.slug}
            href={`/discover/organizations/${o.slug}`}
            style={{ backgroundColor: o.background, color: o.text }}
            className="flex h-24 items-center gap-3.5 rounded-[20px] border border-black/10 px-5 transition-transform duration-200 hover:scale-[1.015]"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={o.imageUrl} alt="" className="h-11 w-11 shrink-0 rounded-full object-cover" />
            <div className="min-w-0">
              <h2 className="line-clamp-1 text-xl font-bold leading-tight">{o.name}</h2>
              {o.description && <p className="mt-0.5 line-clamp-2 text-sm leading-snug opacity-85">{o.description}</p>}
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
