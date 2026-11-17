// Shown the moment you open a page that still has to fetch its content (Discover,
// Featured, People, Now...), so a click always answers right away instead of the old
// page sitting there until the new one is ready. Pages with their own skeleton use theirs.
export default function Loading() {
  return (
    <div aria-busy="true" aria-label="Loading" className="animate-pulse">
      <div className="h-7 w-48 rounded-lg bg-surface" />
      <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {Array.from({ length: 6 }, (_, i) => (
          <div key={i} className={i >= 2 ? "hidden sm:block" : undefined}>
            <div className="aspect-video w-full rounded-xl bg-surface" />
            <div className="mt-3 h-3.5 w-3/4 rounded bg-surface" />
            <div className="mt-2 h-3 w-1/2 rounded bg-surface" />
          </div>
        ))}
      </div>
    </div>
  );
}
