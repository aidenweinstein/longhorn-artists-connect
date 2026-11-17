import Link from "next/link";

const VIEWS = [
  { id: "organizations", href: "/discover/organizations", label: "Organizations" },
  { id: "classes", href: "/discover/classes", label: "Classes" },
] as const;

/** The Groups page's Organizations / Classes toggle, shown at the top of both lists. */
export default function GroupsToggle({ on }: { on: (typeof VIEWS)[number]["id"] }) {
  return (
    <nav aria-label="Groups" className="mb-4 flex w-max items-center gap-0.5 rounded-full bg-foreground/10 p-1">
      {VIEWS.map((v) => (
        <Link
          key={v.id}
          href={v.href}
          aria-current={v.id === on ? "page" : undefined}
          className={`whitespace-nowrap rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
            v.id === on ? "bg-foreground text-background shadow-sm" : "text-foreground/75 hover:bg-foreground/10 hover:text-foreground"
          }`}
        >
          {v.label}
        </Link>
      ))}
    </nav>
  );
}
