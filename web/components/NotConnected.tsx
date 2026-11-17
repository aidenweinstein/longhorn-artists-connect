import Link from "next/link";
import { primaryBtn } from "./AuthShell";

/** Dead-end screen for flows the website can't complete yet, with a way in as a guest (after an email check). */
export default function NotConnected({ heading, body }: { heading: string; body: string }) {
  return (
    <div className="space-y-4 text-center">
      <p className="text-lg font-semibold">{heading}</p>
      <p className="text-sm text-white/65">
        {body}
      </p>
      <Link href="/guest" className={`${primaryBtn} flex items-center justify-center`}>
        Continue as guest
      </Link>
    </div>
  );
}
