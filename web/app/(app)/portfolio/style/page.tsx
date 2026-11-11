import { redirect } from "next/navigation";

/** The old profile-style editor. Actor, Filmmaker and Musician Info now live in Edit profile. */
export default function EditStyle() {
  redirect("/portfolio/edit");
}
