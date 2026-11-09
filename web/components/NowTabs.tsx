// Small building blocks for the Now page (app/(app)/now/page.tsx).

export function SampleNote() {
  return (
    <p className="mt-2 text-xs text-muted">
      Sample data from <code>lib/sampleNow.ts</code>. Real sets and auditions will come from the app.
    </p>
  );
}

export function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mt-10 first-of-type:mt-6">
      <p className="border-b border-border pb-2 text-xs font-semibold uppercase tracking-wider text-muted">{title}</p>
      {children}
    </div>
  );
}

export function Section({ title, count, children }: { title: string; count?: number; children: React.ReactNode }) {
  return (
    <section className="mt-5">
      <h2 className="mb-3 flex items-baseline gap-2 text-xl">
        {title}
        {count !== undefined && <span className="font-sans text-sm font-normal text-muted">{count}</span>}
      </h2>
      {children}
    </section>
  );
}

export function CallLine({ date, time, location, note }: { date: string; time: string; location: string; note?: string }) {
  return (
    <div className="flex gap-3 text-sm">
      <span className="w-24 shrink-0 font-semibold">{date}</span>
      <span className="w-20 shrink-0 tabular-nums text-brand">{time}</span>
      <span className="min-w-0">
        {location}
        {note && <span className="block text-xs text-muted">{note}</span>}
      </span>
    </div>
  );
}
