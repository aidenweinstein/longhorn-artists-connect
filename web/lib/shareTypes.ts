// The Share page's submission types, in the app's order, with the app's taglines
// (SubmissionTypeSubtitles in ShareView.swift).
export const SHARE_TYPES = [
  { id: "film", title: "Film", subtitle: "Frame your vision", icon: "/brand/film.png", ratio: 112 / 128 },
  { id: "music", title: "Music", subtitle: "Sound that resonates", icon: "/brand/music.png", ratio: 74 / 128 },
  { id: "performance", title: "Performance", subtitle: "Take center stage", icon: "/brand/performance.png", ratio: 169 / 128 },
  { id: "photography", title: "Photography", subtitle: "Capture the moment", icon: "/brand/photography.png", ratio: 174 / 128 },
  { id: "design", title: "Design", subtitle: "Paint the walls", icon: "/brand/design.png", ratio: 159 / 128 },
  { id: "project", title: "Project", subtitle: "Building something bigger", icon: "/brand/project.png", ratio: 99 / 128 },
  { id: "event", title: "Event", subtitle: "Gather your people", icon: "/brand/event.png", ratio: 135 / 128 },
] as const;
