export default function Loading() {
  return (
    <div className="mx-auto flex max-w-[1920px] animate-pulse flex-col gap-6 xl:flex-row">
      <div className="min-w-0 flex-1">
        <div className="aspect-video w-full rounded-2xl bg-surface" />
        <div className="mt-5 h-7 w-2/3 rounded-lg bg-surface" />
        <div className="mt-4 flex items-center gap-3">
          <div className="h-11 w-11 rounded-full bg-surface" />
          <div className="h-4 w-40 rounded bg-surface" />
        </div>
        <div className="mt-5 h-40 rounded-2xl bg-surface" />
      </div>
      <div className="flex w-full shrink-0 flex-col gap-3 xl:w-[340px]">
        {Array.from({ length: 6 }, (_, i) => (
          <div key={i} className="flex gap-3">
            <div className="aspect-video w-40 rounded-lg bg-surface" />
            <div className="flex-1 space-y-2 py-1">
              <div className="h-3.5 rounded bg-surface" />
              <div className="h-3 w-2/3 rounded bg-surface" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
