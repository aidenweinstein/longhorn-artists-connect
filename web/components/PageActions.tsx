import { ComposeGlyph, HelpGlyph, InfoGlyph } from "./icons";

const pill = "flex h-9 items-center justify-center rounded-full bg-pill-active font-semibold text-white transition hover:brightness-110";

/** Top-bar buttons for pages that have actions instead of filters, matching the app's toolbar pills. */
export default function PageActions({ kind }: { kind: "share" | "network" }) {
  if (kind === "share") {
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
  return (
    <div className="flex shrink-0 items-center gap-2.5">
      <button type="button" className={`${pill} px-5 text-sm`}>Directory</button>
      <button type="button" aria-label="New message" title="New message" className={`${pill} w-11`}>
        <ComposeGlyph className="h-5 w-5" />
      </button>
    </div>
  );
}
