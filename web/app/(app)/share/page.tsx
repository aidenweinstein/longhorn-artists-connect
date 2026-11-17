import Link from "next/link";
import MaskImage from "@/components/MaskImage";
import { SHARE_TYPES } from "@/lib/shareTypes";

type ShareType = (typeof SHARE_TYPES)[number];

// Projects and events sit on their own row beneath the five kinds of work.
const SECOND_ROW_IDS: readonly string[] = ["project", "event"];
const WORK_TYPES = SHARE_TYPES.filter((t) => !SECOND_ROW_IDS.includes(t.id));
const PLAN_TYPES = SHARE_TYPES.filter((t) => SECOND_ROW_IDS.includes(t.id));

function TypeCard({ t }: { t: ShareType }) {
  return (
    <Link
      href={`/share/${t.id}`}
      className="group flex h-full flex-col items-center gap-4 rounded-2xl bg-surface px-4 pb-5 pt-6 text-center shadow-[0_3px_8px_rgba(0,0,0,0.12)] transition hover:-translate-y-0.5 hover:shadow-[0_8px_18px_rgba(0,0,0,0.18)] active:scale-[0.98]"
    >
      <span className="flex h-24 w-24 items-center justify-center rounded-2xl bg-brand transition group-hover:brightness-110">
        <MaskImage src={t.icon} ratio={t.ratio} className="h-[56px] max-w-[64px] text-white" />
      </span>
      <span>
        <span className="block text-xl font-semibold">{t.title}</span>
        <span className="mt-0.5 block text-[15px] text-muted">{t.subtitle}</span>
      </span>
    </Link>
  );
}

export default function Share() {
  return (
    <div className="mx-auto w-full max-w-4xl py-6 lg:max-w-none">
      <h1 className="text-3xl font-bold">What are you sharing?</h1>
      <p className="mt-1 text-muted">Pick a type to start a new submission.</p>
      {/* Row 1: Film, Music, Performance, Design, Photography — five across on a full-size window. */}
      <ul className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        {WORK_TYPES.map((t) => (
          <li key={t.id}>
            <TypeCard t={t} />
          </li>
        ))}
      </ul>
      {/* Row 2: Project and Event — same card width as row 1, centered beneath it. */}
      <ul className="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-10">
        {PLAN_TYPES.map((t, i) => (
          <li key={t.id} className={`lg:col-span-2 ${i === 0 ? "lg:col-start-4" : ""}`}>
            <TypeCard t={t} />
          </li>
        ))}
      </ul>
    </div>
  );
}
