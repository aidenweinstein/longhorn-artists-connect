import type { ReactNode } from "react";
import { HelpGlyph, InfoGlyph } from "./icons";
import DraftsButton from "./share/DraftsButton";

// Same look as the page bar's other buttons (SubNav): a dark capsule holding one pill.
export const barCapsule = "flex w-max items-center rounded-full bg-black/20 p-1";
export const barPill =
  "flex items-center gap-2 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium text-brand-foreground/85 transition-colors hover:bg-white/15 hover:text-brand-foreground";

function BarButton({ label, glyph }: { label: string; glyph?: ReactNode }) {
  return (
    <div className={barCapsule}>
      <button type="button" aria-label={label} title={label} className={barPill}>
        {glyph}
        {/* Buttons with an icon keep only the icon when the window is narrow (under 1280px,
            like Home's category filter), so the search box stays the size it is on Home. */}
        <span className={glyph ? "hidden xl:inline" : undefined}>{label}</span>
      </button>
    </div>
  );
}

/** Top-bar buttons for the Share page, styled like the rest of the page bar. */
export default function PageActions({ kind }: { kind: "share" }) {
  if (kind !== "share") return null;
  return (
    <div className="flex shrink-0 items-center gap-2">
      <DraftsButton />
      <BarButton label="Posting Information" glyph={<InfoGlyph className="h-4 w-4" />} />
      <BarButton label="Trouble Posting?" glyph={<HelpGlyph className="h-4 w-4" />} />
    </div>
  );
}
