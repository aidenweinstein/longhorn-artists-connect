import type { Metadata } from "next";
import MaskImage from "@/components/MaskImage";
import { CATEGORIES } from "@/lib/categories";
import WelcomeActions from "./WelcomeActions";

export const metadata: Metadata = { title: "Welcome to Nexus" };

export default function Welcome() {
  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-[#121212] px-6 py-16 text-white">
      {/* Burnt-orange glow */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-1/3 left-1/2 h-[80vh] w-[80vh] -translate-x-1/2 rounded-full bg-brand/30 blur-[120px]"
      />

      <div className="relative flex flex-col items-center text-center">
        <MaskImage
          src="/brand/nexus-wordmark.png"
          ratio={636 / 120}
          label="Nexus"
          className="h-14 text-white sm:h-20"
        />
        <p className="mt-6 max-w-md text-lg text-white/75 sm:text-xl">
          Where student filmmakers, musicians, and artists connect with the industry.
        </p>

        <ul className="mt-10 flex flex-wrap justify-center gap-2">
          {CATEGORIES.map((c) => (
            <li
              key={c.id}
              className="flex items-center gap-2 rounded-full bg-white/10 px-3.5 py-1.5 text-sm font-medium text-white/85"
            >
              <MaskImage src={c.icon} ratio={c.ratio} className="h-4 text-brand" />
              {c.label}
            </li>
          ))}
        </ul>

        <div className="mt-12 flex w-full justify-center">
          <WelcomeActions />
        </div>
      </div>

      <p className="absolute bottom-6 text-xs text-white/40">Nexus by Longhorn Artists Connect</p>
    </div>
  );
}
