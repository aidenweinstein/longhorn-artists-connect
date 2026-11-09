"use server";

import { currentAccount } from "@/lib/account";
import { PeopleServiceError, callPeople, peoplePage } from "@/lib/featured";

export async function applyAction(
  category: string,
  form: { name: string; message: string; links: string },
): Promise<{ ok: true } | { ok: false; message: string }> {
  const page = peoplePage(category);
  if (!page) return { ok: false, message: "That page doesn't exist." };
  const current = await currentAccount();
  if (!current) return { ok: false, message: "Sign in with your school email to apply." };
  const name = form.name.trim() || current.account?.name || "";
  if (!name) return { ok: false, message: "Add your name." };
  if (!form.message.trim()) return { ok: false, message: "Tell us a bit about your work." };
  try {
    await callPeople("apply", {
      category: page.slug,
      email: current.session.email,
      profileID: current.account?.profileID || undefined,
      name,
      message: form.message,
      links: form.links,
    });
    return { ok: true };
  } catch (error) {
    return { ok: false, message: error instanceof PeopleServiceError ? error.message : "Couldn't send your application. Try again." };
  }
}
