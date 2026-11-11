import { HelpGlyph, InfoGlyph } from "./icons";

const pill = "flex h-9 items-center justify-center rounded-full bg-pill-active font-semibold text-white transition hover:brightness-110";

/** Top-bar buttons for the Share page, matching the app's toolbar pills. */
export default function PageActions({ kind }: { kind: "share" }) {
  if (kind !== "share") return null;
  return (
    <div className="flex shrink-0 items-center gap-2.5">
      <button type="button" className={`${pill} px-5 text-sm`}>Drafts</button>
      <button type="button" aria-label="About sharing" title="About sharing" className={`${pill} w-11`}>
        <InfoGlyph className="h-5 w-5" />
      </button>
      <button type="button" aria-label="Help" title="Help" className={`${pill} w-11`}>
        <HelpGlyph className="h-5 w-5" />
      </button>
    </div>
  );
}
