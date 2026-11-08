// EXEC-1 (US-EXEC-1-08) — a loading skeleton that mirrors the Today
// list's own card shape (time + title + status pill), shown while the
// first fetch is in flight, instead of a bare spinner.
export default function JobListSkeleton() {
  return (
    <div className="min-h-screen bg-zinc-50">
      <div className="bg-white border-b border-zinc-200 px-4 py-3">
        <div className="h-4 w-20 animate-pulse rounded bg-zinc-200" />
        <div className="mt-2 h-3 w-28 animate-pulse rounded bg-zinc-100" />
      </div>
      <div className="space-y-3 px-4 py-4" aria-label="Loading your day" role="status">
        {[0, 1, 2].map((i) => (
          <div key={i} className="rounded-xl border border-zinc-200 bg-white p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="w-14 shrink-0">
                <div className="h-5 w-12 animate-pulse rounded bg-zinc-200" />
              </div>
              <div className="min-w-0 flex-1 space-y-2">
                <div className="h-4 w-3/4 animate-pulse rounded bg-zinc-200" />
                <div className="h-3 w-1/2 animate-pulse rounded bg-zinc-100" />
              </div>
              <div className="h-5 w-16 shrink-0 animate-pulse rounded-full bg-zinc-200" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
