import Link from "next/link";
import { currentAccount } from "@/lib/account";
import Avatar from "./Avatar";
import { SignInGlyph } from "./icons";

const base =
  "flex flex-col items-center gap-1 rounded-xl px-2 py-2.5 text-[11px] font-medium transition-colors lg:flex-row lg:gap-3 lg:px-3 lg:text-sm";

/** Holds the spot while the session loads, so neither state flashes. */
export function AccountPlaceholder() {
  return (
    <div aria-hidden className={base}>
      <span className="h-7 w-7 rounded-full bg-surface" />
      <span className="h-3 w-12 rounded bg-surface lg:w-20" />
    </div>
  );
}

/** Shown to anyone who isn't signed in. */
export function SignInLink() {
  return (
    <Link href="/signin" className={`${base} border border-brand/40 font-semibold text-brand hover:bg-brand/10`}>
      <SignInGlyph className="h-6 w-6" />
      <span>Sign in</span>
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
    <Link href="/portfolio" title={`Signed in as ${name}`} className={`${base} text-foreground hover:bg-surface`}>
      <Avatar name={name} src={account?.imageUrl} size="sm" />
      <span className="flex min-w-0 max-w-full flex-col text-center lg:text-left">
        <span className="hidden text-[11px] leading-tight text-muted lg:block">Signed in as</span>
        <span className="truncate font-semibold leading-tight">
          <span className="lg:hidden">{name.split(" ")[0]}</span>
          <span className="hidden lg:inline">{name}</span>
        </span>
      </span>
    </Link>
  );
}
