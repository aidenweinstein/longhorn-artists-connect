import Link from "next/link";
import MaskImage from "@/components/MaskImage";
import { SHARE_TYPES } from "@/lib/shareTypes";

export default function Share() {
  return (
    <div className="mx-auto w-full max-w-4xl py-6 xl:max-w-none">
      <h1 className="text-3xl font-bold">What are you sharing?</h1>
      <p className="mt-1 text-muted">Pick a type to start a new submission.</p>
      {/* All seven types side by side in one row on a full-size window. */}
      <ul className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-7">
        {SHARE_TYPES.map((t) => (
          <li key={t.id}>
            <Link
              href={`/share/${t.id}`}
              className="group flex h-full flex-col items-center gap-4 rounded-2xl bg-surface px-4 pb-5 pt-6 text-center shadow-[0_3px_8px_rgba(0,0,0,0.12)] transition hover:-translate-y-0.5 hover:shadow-[0_8px_18px_rgba(0,0,0,0.18)] active:scale-[0.98]"
            >
              <span className="flex h-24 w-24 items-center justify-center rounded-2xl bg-brand transition group-hover:brightness-110">
                <MaskImage src={t.icon} ratio={t.ratio} className="h-[56px] max-w-[64px] text-white" />
              </span>
              <span>
                <span className="block text-xl font-semibold xl:text-lg">{t.title}</span>
                <span className="mt-0.5 block text-[15px] text-muted xl:text-sm">{t.subtitle}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
