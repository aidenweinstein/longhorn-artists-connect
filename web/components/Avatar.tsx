import { initials } from "./ContentGrid";

const SIZES = { sm: "h-7 w-7 text-[10px]", md: "h-11 w-11 text-sm", lg: "h-14 w-14 text-base", feed: "h-9 w-9 text-xs", xl: "h-28 w-28 text-3xl" } as const;

/** Profile picture. Shows initials until real profile photos come from CloudKit. */
export default function Avatar({ name, src, size = "sm" }: { name: string; src?: string; size?: keyof typeof SIZES }) {
  const cls = `${SIZES[size]} shrink-0 rounded-full`;
  if (src) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt="" loading="lazy" className={`${cls} bg-surface object-cover`} />;
  }
  return (
    <span aria-hidden className={`${cls} flex items-center justify-center bg-brand font-semibold text-white`}>
      {initials(name)}
    </span>
  );
}
