import Link from "next/link";
import type { ReactNode } from "react";
import AuthTheme from "./AuthTheme";
import MaskImage from "./MaskImage";

export default function AuthShell({ title, subtitle, children, footer }: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <AuthTheme>
      <div className="relative w-full max-w-md">
        <Link href="/welcome" aria-label="Back to welcome" className="mx-auto mb-8 block w-fit">
          <MaskImage src="/brand/nexus-wordmark.png" ratio={636 / 120} label="Nexus" className="h-8 text-white" />
        </Link>
        <div className="rounded-3xl border border-white/10 bg-white/[0.04] p-8 backdrop-blur">
          <h1 className="text-2xl font-bold">{title}</h1>
          {subtitle && <p className="mt-1.5 text-sm text-white/65">{subtitle}</p>}
          <div className="mt-6">{children}</div>
        </div>
        {footer && <div className="mt-6 text-center text-sm text-white/65">{footer}</div>}
      </div>
    </AuthTheme>
  );
}

export const field =
  "h-12 w-full rounded-xl border border-white/15 bg-black/30 px-4 text-[15px] text-white outline-none placeholder:text-white/40 focus:border-[var(--auth-line)]";
export const primaryBtn =
  "h-12 w-full rounded-full bg-[var(--auth)] text-[15px] font-semibold text-[var(--auth-fg)] transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40";
export const labelCls = "mb-1.5 block text-sm font-medium text-white/80";
