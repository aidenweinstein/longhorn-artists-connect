import Link from "next/link";
import { currentAccount } from "@/lib/account";
import { barCapsule, barPill } from "./PageActions";
import SignOutButton from "./SignOutButton";

const glyph = { width: 16, height: 16, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.8, strokeLinecap: "round", strokeLinejoin: "round" } as const;

// Labels drop away for the icons on a narrow window (under 1280px), like the bar's other buttons.
const label = "hidden xl:inline";

/**
 * Portfolio's top-bar buttons: Edit Profile and Sign Out, each a button of its own.
 * Only for someone signed in; Edit Profile only once the email has a Nexus account.
 * Phones keep these on the portfolio page itself, where there is room for them.
 */
export default async function PortfolioBarActions() {
  const current = await currentAccount();
  if (!current) return null;
  return (
    <div className="hidden shrink-0 items-center gap-2 sm:flex">
      {current.account && (
        <div className={barCapsule}>
          <Link href="/portfolio/edit" aria-label="Edit Profile" title="Edit Profile" className={barPill}>
            <svg {...glyph} aria-hidden>
              <path d="M4 20h4L19.5 8.5a2.1 2.1 0 0 0-3-3L5 17z" />
              <path d="m14.5 7.5 3 3" />
            </svg>
            <span className={label}>Edit Profile</span>
          </Link>
        </div>
      )}
      <div className={barCapsule}>
        <SignOutButton
          className={`${barPill} disabled:opacity-60`}
          label="Sign Out"
          labelClassName={label}
          glyph={
            <svg {...glyph} aria-hidden>
              <path d="M9.5 20.5H6a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2h3.5" />
              <path d="M15.5 16.5 20 12l-4.5-4.5M20 12H9.5" />
            </svg>
          }
        />
      </div>
    </div>
  );
}
