import Link from "next/link";

/** Marks a Mock launch screen, with the way out. */
export default function MockBanner({ className = "" }: { className?: string }) {
  return (
    <p className={`z-10 flex items-center gap-2 rounded-full border border-white/15 bg-white/10 px-3.5 py-1.5 text-xs font-medium text-white/80 ${className}`}>
      <span>Mock launch: nothing is sent or saved</span>
      <Link href="/" className="font-semibold text-white underline underline-offset-4 hover:text-white/80">Exit</Link>
    </p>
  );
}
