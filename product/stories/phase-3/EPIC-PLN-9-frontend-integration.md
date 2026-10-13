# PLN-9 — Frontend Integration

**Epic ID:** PLN-9
**Status:** Planning
**Depends on:** PLN-8
**Goal:** The Planner reads and writes through the Phase 3 API instead of `localStorage`, with the same UX, and existing local data can be imported once.

---

## Context

Two copies of the planner share the same code: `webapp/planningFrontendv2` (standalone) and `webapp/protype-2/src/planner/` (mounted at `/planner`, behind login). `protype-2` already has the Xano client and auth (`src/xano.ts`, `AuthContext.tsx`), so **integration targets `protype-2`**; `planningFrontendv2` stays the localStorage prototype unless told otherwise. State today lives in `App.tsx` / `PlannerApp.tsx` (`useState` + `saveStoredData`).

## Existing Architecture (Do Not Break)

- Handler names and UI behavior in `PlannerApp.tsx` stay the same; only their persistence changes.
- Cost, load and capacity math stay client-side (`costUtils.ts`, `agentUtils.ts`) — the backend stores inputs only.
- Frontend types stay camelCase; the client maps to/from snake_case in one place.
- **Publishing stays local-only:** Publish / Reopen / Bulk-publish controls keep their current in-memory behavior and are not sent to the API (the API rejects `status`). They are clearly marked "not saved yet" until the publishing phase.

## Non-Goals

- No realtime multi-user sync (last write wins; reload picks up others' changes).
- No offline mode.
- No changes to `planningFrontendv2`.

---

## Stories

### US-PLN-9-01 — Typed API client and mappers

**File:** `webapp/protype-2/src/planner/api.ts`

- One function per endpoint; one `toApi*`/`fromApi*` mapper pair per entity (`duration_minutes ↔ duration`, derived `planned_start` and `effective_assignee` mapped onto the existing `Task`/`Timeline` shapes so components don't change).
- Unit-tested mappers (round-trip, null backlog, derived fields).

**Acceptance:** Mapper tests pass with `npm test` style runner already used in `protype-2` (`node --import tsx --test`); no component imports snake_case types.

### US-PLN-9-02 — Load from the hydrated board

- On mount: list workspaces → load the active one via `…/board` (+ settings/models). Loading and error states replace the instant `localStorage` read; an account with no workspaces shows the empty state.

**Acceptance:** First paint shows a loading state; failure shows a retry; switching workspace loads that workspace's board; no `localStorage` reads remain for planner data.

### US-PLN-9-03 — Write-through mutations

- Each handler calls its endpoint; the UI updates optimistically and **reconciles with the response** (server order, derived starts). On failure: revert the optimistic change and show an inline error naming what failed.
- Handlers covered: workspace create/rename/update/delete; agent create/update/visibility/delete; timeline create/move/start-time/delete; task create/edit/place/reorder/delete; settings and models.

**Acceptance:** Every handler has a failure path that restores prior state; after a successful reorder the displayed starts equal the server's derived starts; no handler writes to `localStorage`.

### US-PLN-9-04 — Server-side rule surfacing

- API refusals map to existing UI behavior: occupied-cell move refusal, duplicate names, model-in-use (lists agents), admin-only settings (controls disabled for members).

**Acceptance:** Each refusal in the README's rules table produces a visible, specific message; member sees rate/model controls read-only.

### US-PLN-9-05 — One-time localStorage import

- If legacy planner keys exist and the account has no workspaces, offer **Import local data**: preview counts (workspaces/agents/timelines/tasks), then import in dependency order (settings/models → workspaces → agents → timelines → tasks). Legacy assignee **names** are matched to agents by name within the workspace; unmatched names become `null` and are reported.
- Demo seed data (`INITIAL_*`) is never imported silently.
- After success, legacy keys are renamed (not deleted) to `…_imported_<date>` so the user can recover.

**Acceptance:** Import is all-or-nothing per workspace (a failure rolls that workspace back via the delete cascade and reports); re-running does not duplicate (prompt only when the account is empty); unmatched assignees are listed.

### US-PLN-9-06 — Remove dead persistence

- Delete `loadStoredData`/`saveStoredData` use from `PlannerApp.tsx`; keep demo seeds only for tests/import preview. Update the README of `protype-2` planner usage.

**Acceptance:** `grep localStorage` in `src/planner/` returns only the import module.

---

## Functional Test Plan

End-to-end in `protype-2` against a real (test) Xano account, using the browser (Playwright is already configured: `playwright.config.ts`, `e2e/`). Spec: `e2e/planner-backend.spec.ts`.

| ID | Case | Expected |
|---|---|---|
| FT-PLN-9-01 | Login, open `/planner` on an empty account | Empty state; no errors |
| FT-PLN-9-02 | Create workspace, agents (person + AI), timeline, tasks; reload page | Everything persisted and identical after reload |
| FT-PLN-9-03 | Drag task backlog → timeline → other agent → backlog; reload | Order and derived starts match before/after reload |
| FT-PLN-9-04 | Rename an agent; reload | New name everywhere (timelines, tasks, popover) |
| FT-PLN-9-05 | Drag a timeline onto an occupied cell | Refusal message; nothing moved (also after reload) |
| FT-PLN-9-06 | Remove an agent that has timelines | Tasks appear in backlog; persisted after reload |
| FT-PLN-9-07 | Delete workspace | Gone after reload; other workspace intact |
| FT-PLN-9-08 | Member vs. admin on settings/models | Member read-only; admin edits persist |
| FT-PLN-9-09 | Model in use delete attempt | Message lists agents |
| FT-PLN-9-10 | Force an API failure (offline route) during a move | UI reverts; error shown; reload consistent with server |
| FT-PLN-9-11 | Publish controls | Still work locally, labelled not saved; no API call, no `status` sent |
| FT-PLN-9-12 | Import legacy localStorage with an unmatched assignee | Preview correct; import succeeds; unmatched reported; keys renamed |
| FT-PLN-9-13 | Two browsers, same account: edit in A, reload B | B shows A's changes |
| FT-PLN-9-14 | Integrity audit endpoint after the whole run | Clean |

**Completion gate:** all FT cases pass → record results → move to `completed-epics/`. When PLN-9 completes, Phase 3 is done; publishing is the next phase.

## Test Results

_Not yet run._
