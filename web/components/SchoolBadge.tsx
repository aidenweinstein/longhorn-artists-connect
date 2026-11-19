import { currentSession } from "@/lib/account";
import { schoolForID } from "@/lib/schools";
import OtherSchools from "./OtherSchools";
import SchoolBadgeLink from "./SchoolBadgeLink";

const row = "flex items-center gap-3.5 rounded-xl px-2 py-2 transition-colors hover:bg-surface";

/** Holds the spot while the session loads. */
export function SchoolBadgePlaceholder() {
  return (
    <div aria-hidden className={row}>
      <span className="h-9 w-9 shrink-0 rounded-full bg-surface" />
    </div>
  );
}

/**
 * Your school's logo and name, at the top of the sidebar above the five main pages.
 * It's the school you signed in with. Guests get none (see VisitorOtherSchools).
 * Opens that school's own feed, with only its posts (Home has every school's).
 */
export default async function SchoolBadge() {
  const session = await currentSession();
  // A guest has no school of their own: Home is at the top, with every school under it.
  if (!session) return null;
  const school = schoolForID(session.schoolID);
  return (
    <SchoolBadgeLink slug={school.slug} label={`${school.name}, your school`} className={row}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={school.logo} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
      <span className="whitespace-nowrap font-display text-base font-bold leading-tight opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">
        {school.name}
      </span>
    </SchoolBadgeLink>
  );
}

/**
 * The sidebar's other schools: all but the visitor's own (the home school when signed out).
 * `part` "first" is the ones under "Other Schools", "rest" the ones under "More".
 */
export async function VisitorOtherSchools({ part }: { part: "first" | "rest" }) {
  const session = await currentSession();
  // Guests have no school of their own, so every school is listed, under "Schools".
  if (!session) return <OtherSchools mine={null} part={part} heading={part === "first" ? "Schools" : undefined} />;
  return <OtherSchools mine={schoolForID(session.schoolID).slug} part={part} heading={part === "first" ? "Other Schools" : undefined} />;
}
