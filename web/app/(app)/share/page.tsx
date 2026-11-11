import Link from "next/link";
import MaskImage from "@/components/MaskImage";
import { SHARE_TYPES } from "@/lib/shareTypes";

export default function Share() {
  return (
    <div className="flex min-h-[calc(100vh-7rem)] items-center justify-center py-4">
      {/* A list on smaller screens; all seven side by side in one row on a full-size window. */}
      <ul className="flex w-full max-w-xl flex-col gap-3.5 xl:grid xl:max-w-none xl:grid-cols-7 xl:gap-4">
        {SHARE_TYPES.map((t) => (
          <li key={t.id} className="xl:h-full">
            <Link
              href={`/share/${t.id}`}
              className="flex w-full items-center gap-4 rounded-xl bg-surface px-4 py-3 text-left shadow-[0_3px_8px_rgba(0,0,0,0.15)] transition hover:bg-foreground/10 active:scale-[0.99] xl:h-full xl:flex-col xl:justify-start xl:gap-3 xl:px-3 xl:py-6 xl:text-center"
            >
              <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-xl bg-brand">
                <MaskImage src={t.icon} ratio={t.ratio} className="h-[46px] max-w-[46px] text-white" />
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
