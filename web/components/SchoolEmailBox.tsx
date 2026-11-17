"use client";

import { field, labelCls } from "./AuthShell";
import type { SignupSchool } from "@/lib/signupSchools";

/**
 * School email entry: only the part before "@" is typed. The school decides the rest,
 * with a menu when it has more than one domain.
 */
export default function SchoolEmailBox({ school, domains, id, onID, domain, onDomain }: {
  school: SignupSchool;
  domains: string[];
  id: string;
  onID: (id: string) => void;
  domain: string;
  onDomain: (domain: string) => void;
}) {
  return (
    <div>
      <label htmlFor="email" className={labelCls}>{school.name} email</label>
      <div className={`${field} flex items-center gap-1 focus-within:border-[var(--auth-line)]`}>
        <input
          id="email"
          // Not type="email": only the part before "@" goes here.
          type="text"
          inputMode="email"
          autoComplete="username"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          autoFocus
          value={id}
          // Pasting a whole address keeps just the part before "@".
          onChange={(e) => onID(e.target.value.split("@")[0].replace(/\s/g, ""))}
          aria-describedby="email-domain"
          className="h-full min-w-0 flex-1 bg-transparent text-white outline-none placeholder:text-white/40"
          placeholder={school.idPlaceholder}
        />
        {domains.length > 1 ? (
          <select
            id="email-domain"
            aria-label="Email ending"
            value={domain}
            onChange={(e) => onDomain(e.target.value)}
            className="h-full shrink-0 bg-transparent text-white/70 outline-none"
          >
            {domains.map((d) => (
              <option key={d} value={d}>@{d}</option>
            ))}
          </select>
        ) : (
          <span id="email-domain" className="shrink-0 text-white/55">@{domain}</span>
        )}
      </div>
    </div>
  );
}
