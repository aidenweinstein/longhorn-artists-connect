import { notFound } from "next/navigation";
import SystemCheck from "@/components/SystemCheck";
import { currentSession } from "@/lib/account";
import { isAdmin } from "@/lib/featured";
import { SCHOOLS } from "@/lib/schools";

// Admin-only, and always current.
export const instant = false;

export default async function SystemCheckPage() {
  // Non-admins get a plain 404, so the page's existence isn't advertised.
  if (!isAdmin(await currentSession())) notFound();
  return <SystemCheck schools={SCHOOLS.map((s) => ({ slug: s.slug, name: s.name, color: s.color, logo: s.logo }))} />;
}
