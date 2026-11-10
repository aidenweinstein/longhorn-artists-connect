import { redirect } from "next/navigation";

/** Discover opens on Projects; the calendar is its own tab. */
export default function Discover() {
  redirect("/discover/projects");
}
