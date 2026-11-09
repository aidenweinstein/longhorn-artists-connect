import type { PageIcon } from "@/lib/pages";

const base = {
  width: 24,
  height: 24,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

export function PageGlyph({ icon, className }: { icon: PageIcon; className?: string }) {
  switch (icon) {
    case "home":
      return (
        <svg {...base} className={className} aria-hidden>
          <path d="M3.5 10.5 12 3.5l8.5 7V19a1.5 1.5 0 0 1-1.5 1.5h-4v-6h-6v6H5A1.5 1.5 0 0 1 3.5 19z" />
        </svg>
      );
    case "discover":
      return (
        <svg {...base} className={className} aria-hidden>
          <circle cx="6.5" cy="17" r="3.5" />
          <circle cx="17.5" cy="17" r="3.5" />
          <path d="M3 17V9a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v8M14 17V9a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v8M10 11.5h4M5.5 7V4.5h2.5V7M16 7V4.5h2.5V7" />
        </svg>
      );
    case "share":
      return (
        <svg {...base} className={className} aria-hidden>
          <rect x="3.5" y="3.5" width="17" height="17" rx="4" />
          <path d="M12 8v8M8 12h8" />
        </svg>
      );
    case "network":
      return (
        <svg {...base} className={className} aria-hidden>
          <path d="M21 3 10.5 13.5" />
          <path d="M21 3 14.5 21l-4-7.5L3 9.5z" />
        </svg>
      );
    case "portfolio":
      return (
        <svg {...base} className={className} aria-hidden>
          <circle cx="12" cy="8" r="4" />
          <path d="M4.5 21c0-4.1 3.4-7 7.5-7s7.5 2.9 7.5 7" />
        </svg>
      );
  }
}

export function SearchGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <circle cx="11" cy="11" r="6.5" />
      <path d="m16 16 4.5 4.5" />
    </svg>
  );
}

export function GridGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <rect x="3.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="3.5" width="7" height="7" rx="1.5" />
      <rect x="3.5" y="13.5" width="7" height="7" rx="1.5" />
      <rect x="13.5" y="13.5" width="7" height="7" rx="1.5" />
    </svg>
  );
}

export function SignInGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4" />
      <path d="M10 16l4-4-4-4M14 12H4" />
    </svg>
  );
}

export function RocketGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M12 15l-3-3c1.2-4.4 4.2-7.6 10.5-8.5-.9 6.3-4.1 9.3-8.5 10.5z" />
      <path d="M9 12H5.5l2.5-3.5h4M12 15v3.5L15.5 16v-4" />
      <path d="M6.5 17.5c-1 .5-1.5 2-1.5 2s1.5-.5 2-1.5" />
    </svg>
  );
}

export function StarGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z" />
    </svg>
  );
}

export function HeartGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M12 20s-7.5-4.6-7.5-10A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 7.5 3c0 5.4-7.5 10-7.5 10z" />
    </svg>
  );
}

export function PlaylistGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M4 6h12M4 11h12M4 16h7" />
      <path d="m15 14.5 5 3-5 3z" />
    </svg>
  );
}

export function InfoGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 11v5M12 8h.01" />
    </svg>
  );
}

export function HelpGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M12 2.8 21.2 12 12 21.2 2.8 12z" />
      <path d="M10 9.8a2.1 2.1 0 1 1 3 1.9c-.6.3-1 .8-1 1.5v.3M12 16.2h.01" />
    </svg>
  );
}

export function ComposeGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M11 4.5H6A1.5 1.5 0 0 0 4.5 6v12A1.5 1.5 0 0 0 6 19.5h12a1.5 1.5 0 0 0 1.5-1.5v-5" />
      <path d="M17.5 3.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z" />
    </svg>
  );
}

export function EyeGlyph({ className }: { className?: string }) {
  return (
    <svg {...base} className={className} aria-hidden>
      <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}
