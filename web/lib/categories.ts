export const CATEGORIES = [
  { id: "film", label: "Film", icon: "/brand/film.png", ratio: 112 / 128 },
  { id: "music", label: "Music", icon: "/brand/music.png", ratio: 74 / 128 },
  { id: "performance", label: "Performance", icon: "/brand/performance.png", ratio: 169 / 128 },
  { id: "design", label: "Design", icon: "/brand/design.png", ratio: 159 / 128 },
  { id: "photography", label: "Photography", icon: "/brand/photography.png", ratio: 174 / 128 },
] as const;

/** Which role tags (ROLE_TAGS in profileFields.ts) count as each category, for filtering people. */
export const CATEGORY_ROLES: Record<string, readonly string[]> = {
  film: ["Director", "Producer", "Writer", "Editor", "Cinematographer", "Sound Mixer", "VFX Artist"],
  music: ["Composer", "Singer", "Musician", "Sound Mixer"],
  performance: ["Actor", "Dancer"],
  design: ["Graphic Designer", "Game Designer", "Painter", "Animator"],
  photography: ["Photographer"],
};

export type CategoryId = (typeof CATEGORIES)[number]["id"];

export function getCategory(id: string | undefined) {
  return CATEGORIES.find((c) => c.id === id);
}
