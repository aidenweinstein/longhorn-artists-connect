import { redirect } from "next/navigation";

/** Staff Picks is now Featured; old links still land there. */
export default function StaffPicks() {
  redirect("/featured");
}
