/** Where a person's name links to: their app profile when known, otherwise their name. */
export function personHref(name: string, profileID?: string) {
  return `/portfolio/${encodeURIComponent(profileID || name.trim())}`;
}

/** Placeholder names that shouldn't become links. */
export function isLinkable(name: string) {
  const n = name.trim().toLowerCase();
  return n.length > 0 && n !== "unknown" && !n.endsWith(" & others");
}
