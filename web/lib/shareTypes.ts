// The Share page's submission types, in display order, each with a short line of
// examples of what to post there.
export const SHARE_TYPES = [
  { id: "film", title: "Film", subtitle: "Narrative, documentary, class project...", icon: "/brand/film.png", ratio: 112 / 128 },
  { id: "music", title: "Music", subtitle: "Single, album/EP, music video...", icon: "/brand/music.png", ratio: 74 / 128 },
  { id: "performance", title: "Performance", subtitle: "Theatre show, acting, dance...", icon: "/brand/performance.png", ratio: 169 / 128 },
  { id: "design", title: "Design", subtitle: "Magazine, graphic, drawing...", icon: "/brand/design.png", ratio: 159 / 128 },
  { id: "photography", title: "Photography", subtitle: "Sports, nature, people...", icon: "/brand/photography.png", ratio: 174 / 128 },
  { id: "project", title: "Project", subtitle: "Film shoot, music video, director's workshop...", icon: "/brand/project.png", ratio: 99 / 128 },
  { id: "event", title: "Event", subtitle: "Concert, festival, showcase, mixer...", icon: "/brand/event.png", ratio: 135 / 128 },
] as const;
