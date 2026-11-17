"use client";

import { SCHOOLS } from "@/lib/schools";
import { SIGNUP_SCHOOLS, type SignupSchool } from "@/lib/signupSchools";

/** Each school's logo (public/schools/), by the ID sign-up and lib/schools.ts share. */
const logoFor = (id: string) => SCHOOLS.find((s) => s.slug === id)?.logo;

/** The first step of sign-in and sign-up: each school is a button in its own colors, its logo in a circle before its name. */
export default function SchoolPicker({ onPick }: { onPick: (school: SignupSchool) => void }) {
  return (
    <div className="space-y-3">
      <p className="font-semibold">Select your school</p>
      {SIGNUP_SCHOOLS.map((s) => (
        <button
          key={s.id}
          type="button"
          onClick={() => onPick(s)}
          style={{ backgroundColor: s.color, color: s.onColor }}
          className="flex w-full items-center gap-3 rounded-2xl border border-white/15 p-4 text-left font-semibold transition hover:border-white/50 hover:brightness-110"
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {logoFor(s.id) && <img src={logoFor(s.id)} alt="" className="h-9 w-9 shrink-0 rounded-full object-cover ring-1 ring-white/25" />}
          {s.name}
        </button>
      ))}
    </div>
  );
}
