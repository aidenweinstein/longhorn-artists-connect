import type { Post } from "./mockContent";
import type { Credit } from "./postDetails";

/** Short credit lines for common crew roles; anything else reads "<Role> by". */
const ROLE_PREFIXES: [RegExp, string][] = [
  [/sound|mixer|boom|audio|sfx|foley/i, "Sound by"],
  [/cinematograph|director of photography|^dp$|camera|photograph/i, "Shot by"],
  [/editor/i, "Edited by"],
  [/writer/i, "Written by"],
  [/producer/i, "Produced by"],
  [/composer|score/i, "Music by"],
  [/^(actor|actress|cast|lead)/i, "Starring"],
  [/director/i, "Directed by"],
];

function prefixForRole(role: string) {
  const r = role.trim();
  if (!r) return "With";
  return ROLE_PREFIXES.find(([pattern]) => pattern.test(r))?.[1] ?? `${r} by`;
}

/**
 * On a school's page, a card credits someone from that school. When the post's lead
 * (the director, say) is from another school, the card names the first person credited
 * from this one instead, by their role: "Sound by Abby Weinstein". Everywhere else the
 * card keeps its usual credit.
 */
export function creditForSchool(post: Post, slug: string): Post {
  const leads = post.mainCredits as Credit[] | undefined;
  const leadIsLocal = leads?.length ? leads.some((c) => c.schoolSlug === slug) : post.creatorSchoolSlug === slug;
  if (leadIsLocal) return post;

  const local = (post.details?.creditGroups ?? []).flatMap((g) => g.credits).filter((c) => c.schoolSlug === slug);
  if (!local.length) return post;

  // Everyone from this school sharing the first one's credit line ("Sound by A & B").
  const prefix = prefixForRole(local[0].role);
  const people = [...new Map(local.filter((c) => prefixForRole(c.role) === prefix).map((c) => [c.name, c])).values()];
  const first = people[0];
  return {
    ...post,
    creditPrefix: prefix,
    creator: first.name,
    creatorProfileID: first.profileID,
    creatorAvatarUrl: first.avatarUrl,
    creatorAvatarKey: first.avatarKey,
    creatorSchoolSlug: slug,
    mainCredits: people.length > 1 ? people : undefined,
  };
}
