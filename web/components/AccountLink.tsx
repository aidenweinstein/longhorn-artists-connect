import Link from "next/link";
import { currentAccount } from "@/lib/account";
import Avatar from "./Avatar";
import { SignInGlyph } from "./icons";

const base =
  "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors";

/** Holds the spot while the session loads, so neither state flashes. */
export function AccountPlaceholder() {
  return (
    <div aria-hidden className={base}>
      <span className="h-7 w-7 rounded-full bg-surface" />
    </div>
  );
}

/** Shown to anyone who isn't signed in. */
export function SignInLink() {
  return (
    <Link href="/signin" className={`${base} border border-brand/40 font-semibold text-brand hover:bg-brand/10`}>
      <SignInGlyph className="h-6 w-6 shrink-0" />
      <span className="whitespace-nowrap opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">Sign in</span>
    </Link>
  );
}

/** "Signed in as <name>" with the profile picture, or the Sign in button when signed out. */
export default async function AccountLink() {
  const current = await currentAccount();
  if (!current) return <SignInLink />;
  const { session, account } = current;
  const name = account?.name || session.email.split("@")[0];
  return (
    <Link href="/portfolio" aria-label={`Your profile, ${name}`} title={`Signed in as ${name}`} className={`${base} text-foreground hover:bg-surface`}>
      <Avatar name={name} src={account?.imageUrl} size="sm" />
      <span className="flex min-w-0 flex-col whitespace-nowrap opacity-0 transition-opacity duration-150 group-data-[open=true]/nav:opacity-100">
        <span className="text-[11px] leading-tight text-muted">Signed in as</span>
        <span className="truncate font-semibold leading-tight">{name}</span>
      </span>
    </Link>
  );
}
