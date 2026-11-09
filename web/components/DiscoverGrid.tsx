import Link from "next/link";
import type { DiscoverItem, NexusEvent, Project } from "@/lib/discoverContent";
import { DISCOVER_TYPES } from "@/lib/discoverTypes";
import MaskImage from "./MaskImage";

function Poster({ item }: { item: DiscoverItem }) {
  const type = DISCOVER_TYPES.find((t) => t.id === item.kind)!;
  const src = item.kind === "project" ? item.posterUrl : item.flyerUrl;
  if (src) {
    return (
      <div className="flex w-28 shrink-0 items-start sm:w-32">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={src} alt="" loading="lazy" className="h-auto w-full" />
      </div>
    );
  }
  return (
    <div
      className={`relative flex aspect-[2/3] w-28 overflow-hidden shrink-0 items-center justify-center bg-gradient-to-br sm:w-32 ${
        item.kind === "project" ? "from-[#3a1d08] to-[#bf5700]" : "from-[#2b1240] to-[#c2410c]"
      }`}
    >
      <MaskImage src={type.icon} ratio={type.ratio} className="h-10 text-white/40" />
    </div>
  );
}

function Chip({ children, accent = false }: { children: React.ReactNode; accent?: boolean }) {
  return (
    <span
      className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-semibold ${
        accent ? "bg-brand text-white" : "bg-foreground/10 text-muted"
      }`}
    >
      {children}
    </span>
  );
}

function ProjectInfo({ p }: { p: Project }) {
  const open = p.castNeeded.length + p.crewNeeded.length > 0;
  const status =
    p.castNeeded.length && p.crewNeeded.length
      ? "Cast & Crew Needed"
      : p.castNeeded.length
        ? "Cast Needed"
        : p.crewNeeded.length
          ? "Crew Needed"
          : "Team Assembled";
  return (
    <>
      <p className="text-xs font-medium uppercase tracking-wide text-brand">{p.projectType}</p>
      <h3 className="mt-1 line-clamp-2 font-semibold leading-snug">{p.title}</h3>
      <p className="mt-1 line-clamp-3 text-sm text-muted">{p.logline}</p>
      <div className="mt-auto space-y-1.5 pt-2">
        {p.shootDates && <p className="text-sm text-muted">Shooting {p.shootDates}</p>}
        <Chip accent={open}>{status}</Chip>
      </div>
    </>
  );
}

function EventInfo({ e }: { e: NexusEvent }) {
  return (
    <>
      <p className="text-xs font-medium uppercase tracking-wide text-brand">{e.when}</p>
      <h3 className="mt-1 line-clamp-2 font-semibold leading-snug">{e.title}</h3>
      <p className="mt-1 line-clamp-2 text-sm text-muted">{e.logline}</p>
      <div className="mt-auto space-y-1.5 pt-2">
        <p className="line-clamp-1 text-sm text-muted">
          {e.host} · {e.location}
        </p>
        <Chip accent={e.ticketed}>{e.ticketed ? "Tickets" : "Free"}</Chip>
      </div>
    </>
  );
}

export default function DiscoverGrid({ items }: { items: DiscoverItem[] }) {
  if (items.length === 0) {
    return <p className="py-20 text-center text-muted">Nothing here yet.</p>;
  }
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <Link
          key={item.id}
          href={`/discover/${item.id}`}
          className="flex gap-4 overflow-hidden rounded-xl bg-surface transition-colors hover:bg-foreground/10"
        >
          <Poster item={item} />
          <div className="flex min-w-0 flex-1 flex-col py-3 pr-4">
            {item.kind === "project" ? <ProjectInfo p={item} /> : <EventInfo e={item} />}
          </div>
        </Link>
      ))}
    </div>
  );
}
