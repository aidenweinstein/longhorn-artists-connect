import { currentSession } from "@/lib/account";
import { HOME_SCHOOL, schoolForID } from "@/lib/schools";
import GuestGlows from "./GuestGlows";

/**
 * The guest look: black and white, with the launch page's school glows behind Home
 * (GuestGlows). Dark whatever the device's setting, like the launch page. Buttons and
 * highlights on the page are white with black text; the top bar is black with white
 * text (TopBar's own colors win on a school's page, so those keep the school's colors).
 */
const GUEST_THEME = [
  ":root{color-scheme:dark;--background:#121212;--foreground:#ededed;--surface:#1c1c1e;--border:rgb(255 255 255 / 0.12);--muted:#a1a1aa;--brand:#ffffff;--brand-foreground:#000000}",
  "header[data-topbar]{--brand:#000000;--brand-foreground:#ffffff}",
].join("");

/**
 * Colors the main pages in the signed-in visitor's school colors: its main color for the
 * top bar and buttons, its secondary color (USC and Berkeley gold) for text on them, the
 * same pair a school's own feed uses. At the home school the default UT colors in
 * globals.css stay. Guests (no sign-in) get the black-and-white guest look instead.
 * Another school's feed still shows that school's colors (TopBar sets them on the bar
 * itself, which wins over these).
 */
export default async function SchoolTheme() {
  const session = await currentSession();
  if (!session) {
    return (
      <>
        <style>{GUEST_THEME}</style>
        <GuestGlows />
      </>
    );
  }
  const school = schoolForID(session.schoolID);
  if (school.slug === HOME_SCHOOL.slug) return null;
  return <style>{`:root{--brand:${school.color};--brand-foreground:${school.accent}}`}</style>;
}
