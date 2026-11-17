import { currentSession } from "@/lib/account";
import { HOME_SCHOOL, schoolForID } from "@/lib/schools";

/**
 * Colors the main pages in the signed-in visitor's school colors: its main color for the
 * top bar and buttons, its secondary color (USC and Berkeley gold) for text on them, the
 * same pair a school's own feed uses. Signed out, as a guest, or at the home school, the
 * default UT colors in globals.css stay. Another school's feed still shows that school's
 * colors (TopBar sets them on the bar itself, which wins over these).
 */
export default async function SchoolTheme() {
  const school = schoolForID((await currentSession())?.schoolID);
  if (school.slug === HOME_SCHOOL.slug) return null;
  return <style>{`:root{--brand:${school.color};--brand-foreground:${school.accent}}`}</style>;
}
