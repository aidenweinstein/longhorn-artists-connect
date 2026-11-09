export const CATEGORIES = [
  { id: "film", label: "Film", icon: "/brand/film.png", ratio: 112 / 128 },
  { id: "music", label: "Music", icon: "/brand/music.png", ratio: 74 / 128 },
  { id: "performance", label: "Performance", icon: "/brand/performance.png", ratio: 169 / 128 },
  { id: "design", label: "Design", icon: "/brand/design.png", ratio: 159 / 128 },
  { id: "photography", label: "Photography", icon: "/brand/photography.png", ratio: 174 / 128 },
] as const;

export type CategoryId = (typeof CATEGORIES)[number]["id"];

export function getCategory(id: string | undefined) {
  return CATEGORIES.find((c) => c.id === id);
}
