import { queryWhere, str } from "./client";

/** IDs (uppercase UUID strings, as the app stores them) of the posts a person has liked, newest like first. */
export async function likedPostIDs(userRecordName: string): Promise<string[]> {
  const records = await queryWhere("PostLike", "userID", userRecordName, ["postID", "createdDate"]);
  return records
    .sort((a, b) => (Number(b.fields.createdDate?.value) || 0) - (Number(a.fields.createdDate?.value) || 0))
    .map((r) => str(r, "postID"))
    .filter(Boolean);
}
