import type { Project } from "./discoverContent";
import type { Post } from "./mockContent";

/**
 * The production classes a film or project can be posted under, copied from the app's
 * `ProductionClassCatalog` (SharedSubmissionTypes.swift). A post stores the class in its
 * studio field ("Class or Org"), as "code + name" or one of the earlier wordings below.
 */
export type ProductionClass = {
  slug: string;
  /** The course number, e.g. "RTF 304D". */
  code: string;
  /** The class name without its course number. */
  name: string;
  /** Earlier names this class has been stored under, by the app or the website. */
  legacyNames: string[];
};

export const CLASSES: ProductionClass[] = [
  { slug: "rtf-304d", code: "RTF 304D", name: "Intro to Production", legacyNames: ["304D Intro to Production", "304D"] },
  { slug: "rtf-366k", code: "RTF 366K", name: "Narrative Production", legacyNames: ["Intro to Narrative Production", "RTF 366K Intro to Narrative Production"] },
  { slug: "rtf-343", code: "RTF 343", name: "Advanced Narrative Production", legacyNames: [] },
  { slug: "rtf-367d", code: "RTF 367D", name: "Directing Workshop", legacyNames: ["Director's Workshop", "Directors Workshop"] },
];

export const classFullName = (c: ProductionClass) => `${c.code} ${c.name}`;

/** Lowercased, curly apostrophes straightened, spaces collapsed: the app's matching. */
const normalize = (raw: string) => raw.replace(/’/g, "'").toLowerCase().split(/\s+/).filter(Boolean).join(" ");

/** The class a stored studio value refers to, if any. */
export function classFor(studio: string | undefined): ProductionClass | undefined {
  const key = normalize(studio ?? "");
  if (!key) return undefined;
  return CLASSES.find((c) => [classFullName(c), c.code, c.name, ...c.legacyNames].some((n) => normalize(n) === key));
}

export const classForSlug = (slug: string) => CLASSES.find((c) => c.slug === slug);

/** Films posted under a class. */
export const classFilms = (c: ProductionClass, posts: Post[]) => posts.filter((p) => classFor(p.details?.studio)?.slug === c.slug);

/** Projects on Discover posted under a class. */
export const classProjects = (c: ProductionClass, projects: Project[]) => projects.filter((p) => classFor(p.studio)?.slug === c.slug);
