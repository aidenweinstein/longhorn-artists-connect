import Link from "next/link";
import { currentSession } from "@/lib/account";
import { HOME_SCHOOL, schoolForID } from "@/lib/schools";
import OtherSchools from "./OtherSchools";

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
 * It's the school you signed in with; signed out or browsing as a guest, the home school.
 * Opens that school's feed (Home for the home school).
 */
export default async function SchoolBadge() {
  const school = schoolForID((await currentSession())?.schoolID);
  return (
    <Link href={school.slug === HOME_SCHOOL.slug ? "/" : `/school/${school.slug}`} aria-label={`${school.name}, your school`} className={row}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={school.logo} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover" />
      <span className="whitespace-nowrap font-display text-base font-bold leading-tight opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">
        {school.name}
      </span>
    </Link>
  );
}

/** The sidebar's other schools: all but the visitor's own (the home school when signed out). */
export async function VisitorOtherSchools() {
  return <OtherSchools mine={schoolForID((await currentSession())?.schoolID).slug} />;
}
