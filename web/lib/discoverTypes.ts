export const DISCOVER_TYPES = [
  { id: "project", label: "Projects", icon: "/brand/project.png", ratio: 99 / 128 },
  { id: "event", label: "Events", icon: "/brand/event.png", ratio: 135 / 128 },
] as const;

export type DiscoverType = (typeof DISCOVER_TYPES)[number]["id"];
