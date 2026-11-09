import Link from "next/link";
import MaskImage from "@/components/MaskImage";
import { SHARE_TYPES } from "@/lib/shareTypes";

export default function Share() {
  return (
    <div className="flex min-h-[calc(100vh-7rem)] items-center justify-center py-4">
      <ul className="flex w-full max-w-xl flex-col gap-3.5">
        {SHARE_TYPES.map((t) => (
          <li key={t.id}>
            <Link
              href={`/share/${t.id}`}
              className="flex w-full items-center gap-4 rounded-xl bg-surface px-4 py-3 text-left shadow-[0_3px_8px_rgba(0,0,0,0.15)] transition hover:bg-foreground/10 active:scale-[0.99]"
            >
              <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-xl bg-brand">
                <MaskImage src={t.icon} ratio={t.ratio} className="h-[46px] max-w-[46px] text-white" />
              </span>
              <span>
                <span className="block text-xl font-semibold">{t.title}</span>
                <span className="block text-[15px] text-muted">{t.subtitle}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
