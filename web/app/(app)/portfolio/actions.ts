"use server";

import { updateTag } from "next/cache";
import { creditedPosts, currentAccount } from "@/lib/account";
import { updateFields, type CKField } from "@/lib/cloudkit/client";
import { accountTag } from "@/lib/cloudkit/content";
import { isTileSize, serializeTileSizes, type TileSizes } from "@/lib/portfolioLayout";

export type SaveLayoutResult = { ok: true; warning?: string } | { ok: false; message: string };

/**
 * Saves the signed-in visitor's portfolio grid. The order goes to portfolioOrder,
 * the same field the app uses, so both show the same order; sizes go to portfolioLayout.
 *
 * This is the one thing a web session may write: only the session's own linked
 * account, only these two fields, and only posts that account is credited on.
 */
export async function savePortfolioLayout(order: unknown, sizes: unknown): Promise<SaveLayoutResult> {
  const current = await currentAccount();
  const userRecordName = current?.session.userRecordName;
  if (!current?.account || !userRecordName) {
    return { ok: false, message: "Sign in with an email linked to your Nexus account to edit your portfolio." };
  }
  if (!Array.isArray(order) || order.length > 1000 || !sizes || typeof sizes !== "object") {
    return { ok: false, message: "That layout couldn't be read. Reload and try again." };
  }

  // Keep only the account's own credited posts, using the server's IDs.
  const mine = new Map((await creditedPosts(current.account)).map((p) => [p.id.toUpperCase(), p.id]));
  const ids: string[] = [];
  for (const raw of order) {
    const id = typeof raw === "string" ? mine.get(raw.toUpperCase()) : undefined;
    if (id && !ids.includes(id)) ids.push(id);
  }
  const cleanSizes: TileSizes = {};
  for (const [raw, size] of Object.entries(sizes as Record<string, unknown>)) {
    const id = mine.get(raw.toUpperCase());
    if (id && isTileSize(size)) cleanSizes[id] = size;
  }

  const recordName = `UserProfile_${userRecordName}`;
  const orderField: Record<string, CKField> = ids.length ? { portfolioOrder: { value: ids, type: "STRING_LIST" } } : {};
  try {
    let error = await updateFields("UserProfile", recordName, {
      ...orderField,
      portfolioLayout: { value: serializeTileSizes(cleanSizes), type: "STRING" },
    });
    let warning: string | undefined;
    // Until portfolioLayout is added to the production schema, still save the order.
    if (error && /portfolioLayout/i.test(error.reason) && ids.length) {
      error = await updateFields("UserProfile", recordName, orderField);
      warning = "Your order was saved, but tile sizes can't be saved until the portfolioLayout field is added in CloudKit.";
    }
    if (error) {
      console.error("[portfolio] save failed:", error.code, error.reason);
      return { ok: false, message: "Couldn't save your layout. Try again in a moment." };
    }
    updateTag(accountTag(userRecordName));
    return warning ? { ok: true, warning } : { ok: true };
  } catch (e) {
    console.error("[portfolio] save failed:", e instanceof Error ? e.message : e);
    return { ok: false, message: "Couldn't save your layout. Try again in a moment." };
  }
}
