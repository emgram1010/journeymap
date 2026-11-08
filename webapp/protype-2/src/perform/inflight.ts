// PERF-1 (US-PERF-1-04) — share one in-flight request between callers
// that ask for exactly the same thing at the same moment.
//
// WHY THIS, AND NOT PARALLEL LOADING. Measured live (2026-11-02): the
// Xano backend works through one account's requests roughly ONE AT A
// TIME — board alone ~3.2s, backlog alone ~2.3s, both at once ~5.8s
// wall (the sum, not the max). So starting requests earlier or in
// parallel cannot shorten the wait; only sending FEWER requests can.
// And the planner was sending duplicates: React StrictMode mounts every
// component twice in dev, so the plan list, the jobs list and the
// backlog were each requested twice on every load — ~4s of extra work
// queued on the same backend. Two callers asking for the same URL while
// the first request is still in flight now share it.
//
// IN-FLIGHT ONLY — NOTHING IS CACHED. The entry is removed the moment
// the request settles, so the next ask after that (a refetch after a
// write, a reload) always goes to the network. The only thing two
// callers ever share is a response that was going to arrive at the
// same moment for both anyway.
//
// PURE — no fetch, no React. Tested in inflight.test.ts.

export function createInflight<T>() {
  const pending = new Map<string, Promise<T>>();

  return function share(key: string, run: () => Promise<T>): Promise<T> {
    const existing = pending.get(key);
    if (existing) return existing;
    const promise: Promise<T> = run().finally(() => {
      if (pending.get(key) === promise) pending.delete(key);
    });
    pending.set(key, promise);
    return promise;
  };
}
