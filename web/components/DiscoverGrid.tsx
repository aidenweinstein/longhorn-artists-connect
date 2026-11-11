import Link from "next/link";
import type { DiscoverItem, NexusEvent, Project } from "@/lib/discoverContent";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";
import { PRODUCTION_CLASSES } from "@/lib/shareOptions";
import MaskImage from "./MaskImage";

const dateFmt = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric" });

/** The poster (projects) or flyer (events) at full column width, like the home feed's thumbnails. */
function Poster({ item }: { item: DiscoverItem }) {
  const type = DISCOVER_TYPES.find((t) => t.id === item.kind)!;
  const src = item.kind === "project" ? item.posterUrl : item.flyerUrl;
  const open = item.kind === "project" && item.castNeeded.length + item.crewNeeded.length > 0;
  return (
    <div className="relative overflow-hidden rounded-xl transition-transform duration-200 group-hover:scale-[1.015]">
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt="" loading="lazy" className="block h-auto w-full" />
      ) : (
        <div
          className={`flex aspect-[2/3] w-full items-center justify-center bg-gradient-to-br ${
            item.kind === "project" ? "from-[#3a1d08] to-[#bf5700]" : "from-[#2b1240] to-[#c2410c]"
          }`}
        >
          <MaskImage src={type.icon} ratio={type.ratio} className="h-14 text-white/35" />
        </div>
      )}
      {open && (
        <span className="absolute bottom-2 right-2 rounded-md bg-brand px-1.5 py-0.5 text-xs font-semibold text-white">
          {statusLabel(item as Project)}
        </span>
      )}
    </div>
  );
}

function statusLabel(p: Project) {
  if (p.castNeeded.length && p.crewNeeded.length) return "Cast & Crew Needed";
  return p.castNeeded.length ? "Cast Needed" : "Crew Needed";
}

/** "Director", "Co-Director" count; "Director of Photography", "Casting Director", "Art Director", "Assistant Director" don't. */
function isDirector(role: string) {
  const r = role.toLowerCase();
  return r.includes("director") && !/photography|casting|art director|assistant|1st ad|2nd ad/.test(r);
}

function joinNames(names: string[]) {
  return names.length > 1 ? `${names.slice(0, -1).join(", ")} & ${names.at(-1)}` : names[0];
}

/** "Class · RTF 366K Narrative Production", "Org · Collective" or "Independent". */
function affiliation(studio?: string) {
  const s = studio?.trim();
  if (!s || s.toLowerCase() === "independent") return "Independent";
  const isClass = PRODUCTION_CLASSES.some((c) => c.toLowerCase() === s.toLowerCase()) || /^RTF \d/i.test(s);
  return `${isClass ? "Class" : "Org"} · ${s}`;
}

function Line({ children }: { children: React.ReactNode }) {
  return <p className="line-clamp-1 text-sm text-muted">{children}</p>;
}

function ProjectInfo({ p }: { p: Project }) {
  const directors = (p.crewAssembled ?? []).filter((c) => isDirector(c.role)).map((c) => c.name);
  const shoot = p.shootDates ?? (p.shootStart ? dateFmt.format(new Date(p.shootStart)) : undefined);
  return (
    <>
      {directors.length ? (
        <Line>Directed by {joinNames(directors)}</Line>
      ) : (
        p.postedBy && <Line>Posted by {p.postedBy}</Line>
      )}
      {shoot && <Line>Shoot Dates: {shoot}</Line>}
      <Line>{affiliation(p.studio)}</Line>
    </>
  );
}

function EventInfo({ e }: { e: NexusEvent }) {
  const when = e.when || (e.startsAt ? dateFmt.format(new Date(e.startsAt)) : "");
  return (
    <>
      {e.host && <Line>Hosted by {e.host}</Line>}
      {when && <Line>{when}</Line>}
      {e.location && <Line>{e.location}</Line>}
    </>
  );
}

function Card({ item }: { item: DiscoverItem }) {
  return (
    <Link href={`/discover/${item.id}`} className="group block">
      <Poster item={item} />
      <div className="mt-3 min-w-0">
        <h3 className="mb-1 line-clamp-2 text-[15px] font-semibold leading-snug">{item.title}</h3>
        {item.kind === "project" ? <ProjectInfo p={item} /> : <EventInfo e={item} />}
      </div>
    </Link>
  );
}

/** Deals items across columns left to right, so the list's order reads along each row. */
function Columns({ items, count, className }: { items: DiscoverItem[]; count: number; className: string }) {
  const cols: DiscoverItem[][] = Array.from({ length: count }, () => []);
  items.forEach((item, i) => cols[i % count].push(item));
  return (
    <div className={`items-start gap-4 ${className}`}>
      {cols.map((col, i) => (
        <div key={i} className="flex min-w-0 flex-1 flex-col gap-8">
          {col.map((item) => (
            <Card key={item.id} item={item} />
          ))}
        </div>
      ))}
    </div>
  );
}

/** Projects or events as a poster feed: large posters in three columns with a few details underneath, like the home feed. */
export default function DiscoverGrid({ items }: { items: DiscoverItem[] }) {
  if (items.length === 0) {
    return <p className="py-20 text-center text-muted">Nothing here yet.</p>;
  }
  return (
    <>
      <Columns items={items} count={1} className="flex sm:hidden" />
      <Columns items={items} count={2} className="hidden sm:flex lg:hidden" />
      <Columns items={items} count={3} className="hidden lg:flex" />
    </>
  );
}
