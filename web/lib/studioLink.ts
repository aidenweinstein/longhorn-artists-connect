import { ORGANIZATIONS } from "./organizations";
import { classFor } from "./productionClasses";

const normalize = (raw: string) => raw.replace(/[‘’]/g, "'").toLowerCase().split(/\s+/).filter(Boolean).join(" ");

/**
 * The page for a post's Org/Class (its studio field), when it names one: a production
 * class's page (/discover/classes/<slug>) or an organization's
 * (/discover/organizations/<slug>), matched by name. Anything else has no page.
 */
export function studioHref(studio: string | undefined): string | undefined {
  if (!studio?.trim()) return undefined;
  const cls = classFor(studio);
  if (cls) return `/discover/classes/${cls.slug}`;
  const key = normalize(studio);
  const org = ORGANIZATIONS.find((o) => normalize(o.name) === key || o.slug === key);
  return org ? `/discover/organizations/${org.slug}` : undefined;
}
