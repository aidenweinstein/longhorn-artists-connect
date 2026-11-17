import MaskImage from "@/components/MaskImage";
import { CATEGORIES } from "@/lib/categories";
import SchoolGlows from "@/components/SchoolGlows";
import MockBanner from "@/components/MockBanner";
import WelcomeActions from "./WelcomeActions";

/** The launch page. `mock` is the Mock launch walkthrough: same page, but nothing is sent or saved. */
export default function WelcomeScreen({ mock = false }: { mock?: boolean }) {
  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-[#121212] px-6 py-16 text-white">
      <SchoolGlows />

      {mock && <MockBanner className="absolute top-6" />}

      <div className="relative flex flex-col items-center text-center">
        <MaskImage
          src="/brand/nexus-wordmark.png"
          ratio={636 / 120}
          label="Nexus"
          className="h-14 text-white sm:h-20"
        />
        <p className="mt-6 max-w-xl text-lg text-white/75 sm:text-xl">
          The social hub for college creators. Share film, music, performance, design, and photography work with classmates and future collaborators.
        </p>

        <ul className="mt-10 flex flex-wrap justify-center gap-2">
          {CATEGORIES.map((c) => (
            <li
              key={c.id}
              className="flex items-center gap-2 rounded-full bg-white/10 px-3.5 py-1.5 text-sm font-medium text-white/85"
            >
              <MaskImage src={c.icon} ratio={c.ratio} className="h-4 text-white/70" />
              {c.label}
            </li>
          ))}
        </ul>

        <div className="mt-12 flex w-full justify-center">
          <WelcomeActions mock={mock} />
        </div>
      </div>

      <p className="absolute bottom-6 flex flex-wrap justify-center gap-x-3 gap-y-1 px-6 text-xs text-white/40">
        <span>Nexus by Longhorn Artists Connect</span>
        <a
          href="https://collegeartistsconnect.org"
          target="_blank"
          rel="noopener noreferrer"
          className="underline underline-offset-2 transition-colors hover:text-white"
        >
          collegeartistsconnect.org
        </a>
      </p>
    </div>
  );
}
