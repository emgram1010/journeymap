# EPIC-RES-4 — DB-Side Filtering & Pagination

> 🟡 **EXECUTOR MODEL — higher model resolves the open decisions FIRST, then 4.6
> implements.** Open calls: where `intent` actually lives (it's not a column) and the
> pagination contract. The `where`/`$auth` scoping pattern itself is copyable → 4.6.

**Layer:** Logic · **Status:** Not started
**Scheduling:** **Parallel with** RES-5, RES-6, RES-3, RES-8
**Blocked by** RES-0, RES-2 · **Unblocks:** RES-7

---

## Goal

No read endpoint loads a whole table into memory. Every list/search filters and
paginates at the database, scoped to the tenant.

## Why (resilience rationale)

`list_maps` currently loads the entire `journey_map` table then filters in a `foreach`;
`search` loads all of an account's maps then string-matches in memory. Both are
O(table) per call and `list_maps` has no tenant scoping at all — a correctness, scale,
and isolation problem simultaneously. Pushing predicates into `db.query` with paging
makes cost proportional to the page, not the corpus.

---

## Stories

### US-RES-4-01 — Tenant scope on list_maps
**Change:** Add `account_id` (and `owner_user` where relevant) to the `where` clause so
the endpoint can never return cross-tenant rows.
**Acceptance:**
- No call returns a map outside the caller's account.
- Verified by a cross-tenant access test.

### US-RES-4-02 — Push filters into the query
**Change:** Move `status`, `intent`, `map_level`, `architecture_id` from in-memory
`foreach` filtering into the `db.query where`.
**Acceptance:**
- The endpoint issues a single filtered query; no post-query `foreach` filter remains.

### US-RES-4-03 — Add pagination
**Change:** Add `limit` + `offset` (or cursor) inputs and return paging metadata.
**Acceptance:**
- Default page size is bounded; callers can page through results.
- Response includes total/next-cursor metadata.

### US-RES-4-04 — DB-side search
**Change:** Replace in-memory `ai_summary`/`tags` string matching in `search` with a
DB-side text/predicate search, tenant-scoped + paginated.
**Acceptance:**
- Search never loads the full account corpus into memory.
- Results match the previous semantics for existing queries.

### US-RES-4-05 — Bound other list endpoints
**Change:** Audit remaining `return: "list"` queries (e.g. raw `journey_cell_GET`) for
unbounded reads; scope or paginate them.
**Acceptance:**
- No endpoint returns an unbounded full-table list.

---

## Executor Contract (read before coding)

**Touchpoints (only):**
- `tools/54_list_maps.xs` — lines ~24-28 load the whole table; ~34-87 filter in `foreach`.
- `api/journey_map/journey_map/search_GET.xs` — lines ~29-33 load candidates; ~44-112
  text-match in memory (note: this one **is** already account-scoped — keep that).
- `api/journey_map/journey_cell_GET.xs` — unbounded `return: {type:"list"}` with no `where`.

**Real anchors / defects to handle (not silently drop):**
- `list_maps` has **no `$auth` scoping at all** — it can return cross-tenant maps. Add
  account scoping. Copy the `$auth` → `db.get user` → `account_id` pattern from
  `search_GET.xs` (lines 23-33).
- `list_maps` filters on `$m.intent` but `intent` is **not a column** in
  `table/journey_map.xs`. → **Stop-and-ask** where `intent` lives (likely `settings`)
  before moving that filter into the `where`. Do not delete the filter to make it compile.

**Do NOT touch:** the response **keys** already returned (`id, title, intent, status,
map_level, last_interaction_at` for list; the search result keys). Add paging metadata
**additively**. Any shape change must be mirrored in the RES-7 PR, same release.

**Verify with:**
- Cross-tenant test: a user in account A never receives an account-B map (0 leakage).
- Telemetry (RES-8) shows rows-returned bounded by page size, not table size.
- For existing inputs, the result set matches the old behavior minus the tenant leak.

**Parity:** same logical results for the same filters; only scoping + paging added.

## Definition of Done

- All list/search endpoints are tenant-scoped, filtered, and paginated at the DB.
- Row-count telemetry (RES-8) shows bounded reads.
- Response-shape change is documented for RES-7 to consume in the same release.
