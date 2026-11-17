"use client";

import { createContext, useContext, useState, type CSSProperties, type ReactNode } from "react";
import type { SignupSchool } from "@/lib/signupSchools";
import SchoolGlows from "./SchoolGlows";

/**
 * The look of the sign-in and sign-up screens. With no school picked they are black,
 * white and gray. Once a form picks a school (`useAuthSchool`), buttons, outlines, links
 * and the glow switch to that school's colors.
 *
 * Styles read three variables: --auth (button fill), --auth-fg (text on it) and
 * --auth-line (outlines, links, progress: a color that reads on black).
 */
const AuthSchool = createContext<(school: SignupSchool | null) => void>(() => {});

/** Call with the school picked, or null to go back to black and white. */
export const useAuthSchool = () => useContext(AuthSchool);

export default function AuthTheme({ children }: { children: ReactNode }) {
  const [school, setSchool] = useState<SignupSchool | null>(null);
  const vars = {
    "--auth": school?.color ?? "#ffffff",
    "--auth-fg": school?.onColor ?? "#000000",
    "--auth-line": school?.highlight ?? "#ffffff",
  } as CSSProperties;
  return (
    <AuthSchool.Provider value={setSchool}>
      <div
        style={vars}
        className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden bg-[#121212] px-6 py-16 text-white"
      >
        <SchoolGlows only={school ?? undefined} />
        {children}
      </div>
    </AuthSchool.Provider>
  );
}
