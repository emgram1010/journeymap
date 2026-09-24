# Emgram Planner — Remaining UX Fixes

**Instructional prompt for Claude Code.** Paste this whole file (or point Claude Code at it) to resume the UX/MVP audit fixes. This picks up after Batch A (correctness fixes) and two Batch B items were already implemented and verified in a separate environment before the frontend was moved into this repo.

---

## 1. Context you need before touching code

This is a React + TypeScript SPA (Vite) called "Emgram Planner" — a business-process planning tool. Agents have per-day Timelines; Timelines contain sequential Tasks. Data persists to `localStorage`.

**Key files:**
- `src/types.ts` — `Workspace`, `Timeline` (has `startTime: string`, the cascade anchor), `Task` (`seq`, `planned_start`, `duration`, `status`, `needsInfoReason`)
- `src/utils/planningLogic.ts` — `recomputeTimelineTaskTimes(timeline, orderedTasks)` cascades every task's `planned_start` from `timeline.startTime` + accumulated `duration`, in `seq` order. `getTimelineReadiness(timeline, timelineTasks, workspace)` returns `{ready, reasons[]}` — checks task count, planning-window date, and `needs_info` tasks. **Don't reinvent either of these — every publish/readiness check in the app should already route through `getTimelineReadiness`, and every task/timeline mutation should route through `App.tsx`'s `recomputeTimeline(allTasks, timelineId, timelineOverride?)` helper.**
- `src/utils/agentUtils.ts` — `calculateAgentDayLoad(agent, date, timelines, tasks)` (single day) and `calculateAgentRangeLoad(agent, visibleDates, timelines, tasks)` (multi-day aggregate, used by the roster — this is what Story C2 below needs to stop using for the blocked/over badges).
- `src/components/BacklogDrawer.tsx`, `ScheduleGrid.tsx`, `DayBoard.tsx`, `Header.tsx`, `AgentRosterRail.tsx`, `EditModal.tsx` — the main UI surfaces referenced below.
- `src/App.tsx` — central state container; `activeDay` (single string date) is the day currently shown on the Day Board — this is the "day on screen" referenced in Story C2, as distinct from `visibleDates` (the full Schedule Grid range, e.g. 14 days).

**Status legend:**
- ✅ **Done** — implemented and verified working before the handoff; treat as reference/regression-check only.
- 🟡 **Spec confirmed, not coded** — audit behavior was manually verified in the running app (e.g. "this nav icon does nothing when clicked"), but no code was written.
- ⬜ **Not started**
- 🚫 **Blocked — spec incomplete** — do not guess at these; ask the user for the missing text first.

Work top to bottom (Epic B → H) unless the user says otherwise. After each story, run the app and manually verify the acceptance criteria before moving to the next — don't batch fixes and verify at the end.

---

## Epic A — Backlog Panel Streamlining *(✅ Done — regression check only)*

### Story A1: Collapsible backlog panel
**Status:** ✅ Done
**User story:** As a planner, I want the backlog panel collapsed by default so it doesn't dominate the screen, so I can focus on the schedule and open it only when I need it.
**Acceptance criteria:**
- Backlog panel has a chevron toggle, collapsed by default on load.
- Expanded state is capped at ~30% viewport height (`max-h-[30vh]`) with internal scroll — it must never clip menus or push the add-task row off-screen.
- All UI copy says "Backlog", never "Bucket" (including the empty state: "Backlog empty — all workspace tasks are placed on timelines.").

### Story A2: Simplified backlog row actions
**Status:** ✅ Done
**User story:** As a planner, I want backlog rows to show only the actions I actually use, so the row isn't cluttered with a non-functional checkbox and a menu for a single action.
**Acceptance criteria:**
- No checkbox on backlog rows.
- No "…" overflow menu on backlog rows — replaced with a single direct trash icon button that deletes the task (no confirmation dialog, matching prior behavior).
- "Add to timeline…" button unchanged (opens the agent/day picker; correctly detects published/locked target timelines and disables submission with an explanatory message; creates a new draft timeline when the target agent/day has none).

---

## Epic B — Signal Simplification ("show exceptions only")

### Story B1: Remove redundant "ready" signals
**Status:** ⬜ Not started
**Short description:** Ready/planned tasks currently get positive-signal chips and checkmarks that add visual noise for the common case. Silence should mean "ready."
**User story:** As a planner scanning a busy board, I want ready tasks to show no extra chrome, so the only things that catch my eye are the ones that actually need my attention.
**Acceptance criteria:**
- The "Planned" chip on individually-ready tasks is removed.
- The "All n tasks planned" summary chip (wherever it currently renders — column header and/or timeline detail) is removed.
- Green checkmarks that currently mark ready/planned state are removed.
- A ready task's row/chip shows no status decoration at all beyond its normal content (title, time, duration).

### Story B2: Blocked shown in exactly two places
**Status:** ⬜ Not started
**Short description:** Consolidate all "blocked" signaling down to two locations: the task's own chip and a count on the column header.
**User story:** As a planner, I want blocked-task signals in one predictable pair of places, so I'm not hunting across the UI to find out what's blocked and why.
**Acceptance criteria:**
- The blocked task's own chip shows the blocked reason (`needsInfoReason`), **never truncated** — wrap the text, don't ellipsis it.
- The column header shows a blocked count (e.g. "2 blocked") when that agent/day has blocked tasks.
- Every other blocked signal elsewhere in the app (roster badges are handled separately in Story C2 — don't touch those here; this is about removing *duplicate* signals in the Day Board / Schedule Grid / task list chrome) is removed.

### Story B3: Published shown by column chip + lock icons only
**Status:** ⬜ Not started
**Short description:** One consistent way to know a timeline is published, and exactly one "Reopen to edit" action — not two competing controls for the same timeline.
**User story:** As a planner, I want a single, consistent way to tell a timeline is published and a single way to reopen it, so I don't second-guess which control is the "real" one.
**Acceptance criteria:**
- Published state is communicated only via: (a) the column/board status chip, and (b) lock icons on the published timeline's tasks.
- Exactly one "Reopen to edit" control exists per timeline view context (e.g. it's fine to have one in the column header for board view and a separate one in Focus mode's banner, since those are mutually exclusive views of the same timeline — but never two simultaneously-visible reopen controls for the same on-screen timeline).
- Remove any other redundant published-state indicators found during implementation.

---

## Epic C — Roster Accuracy

### Story C1: Remove window-total capacity from roster cards
**Status:** ⬜ Not started
**Short description:** Capacity totals belong on the column header and the grid load bar — not duplicated on roster cards.
**User story:** As a planner, I want capacity numbers shown in one place (the schedule grid), so the roster list stays focused on identifying agents and isn't cluttered with a second, easily-stale capacity readout.
**Acceptance criteria:**
- The "`n`h / `total`h" window-total text is removed from `AgentRosterRail.tsx` roster cards entirely (this was computed via `calculateAgentRangeLoad`'s `loadLabel` — remove that display, not the whole roster card).
- Capacity totals continue to render correctly on the Schedule Grid's column headers and load bars (don't touch those).
- Roster cards keep agent name, role/type badges, and the attention markers from Story C2.

### Story C2: Roster Blocked/Over badges reflect the day on screen, not the whole window
**Status:** ⬜ Not started
**Short description:** The roster's "Blocked" / "Over" badges currently aggregate across the entire visible date range (e.g. all 14 days), which is misleading — they should reflect only the single day currently shown on the Day Board.
**User story:** As a planner looking at Monday's board, I want the roster's Blocked/Over badges to describe Monday specifically, so I'm not alarmed by a badge that's actually about a different day I'm not even looking at.
**Acceptance criteria:**
- `AgentRosterRail` takes a new `activeDate: string` prop, wired from `App.tsx`'s existing `activeDay` state.
- The roster's per-agent blocked/over computation uses `calculateAgentDayLoad(agent, activeDate, timelines, tasks)` (single-day) instead of `calculateAgentRangeLoad(agent, visibleDates, timelines, tasks)` (whole-window) for the Blocked/Over badges specifically.
- Changing the Day Board's date (`activeDay`) updates the roster badges live to match that day.
- `calculateAgentRangeLoad` / `visibleDates` can still be used elsewhere in the app (e.g. Schedule Grid) — this story only changes what drives the roster's Blocked/Over badges.

---

## Epic D — Navigation Cleanup

### Story D1: Remove dead nav items
**Status:** 🟡 Spec confirmed, not coded — verified by clicking each: none of the three do anything.
**Short description:** Three nav elements in the left rail are non-functional and should be removed rather than left as decoys.
**User story:** As a planner, I want every visible control to do something, so I don't waste time clicking dead UI trying to find a feature that isn't there.
**Acceptance criteria:**
- The "Component Sheet" nav icon (the stacked-layers icon in the left rail, below the calendar/Plan icon) is removed.
- The Settings gear icon (bottom of the left rail) is removed.
- The avatar menu (bottom-most circular avatar, e.g. "MV") is removed.
- Restore any of the three only if/when they're wired to real functionality — don't leave placeholders.

---

## Epic E — Schedule Grid Polish

### Story E1: Remove legend strip, move meanings to tooltips
**Status:** ⬜ Not started
**Short description:** The Schedule Grid currently has a persistent legend strip (Planned Load / Over Capacity / Blocked Step / Published (Locked) / drag-and-drop hint) taking up permanent screen space. Move those explanations into tooltips on the elements themselves.
**User story:** As a planner, I want the grid's icon/color meanings available on hover rather than permanently occupying a strip of screen space, so I get more room for the actual schedule.
**Acceptance criteria:**
- The legend strip at the bottom of `ScheduleGrid.tsx` is removed.
- Each symbol/color it explained (black load bar = Planned Load, orange = Over Capacity (Warning), blocked-step icon, published/lock icon) gets a `title` tooltip on the actual element in the grid conveying the same explanation.
- The "Drag cell horizontally to re-date · Vertically to re-assign · Refused on occupied cell" hint text is preserved as a tooltip somewhere reasonable (e.g. on the grid header or a help icon) rather than deleted outright.

### Story E2: Empty Day Board columns get an "Add task" row
**Status:** ⬜ Not started
**Short description:** Columns with zero tasks currently show only an empty state; they should offer a direct way to add a task, matching non-empty columns.
**User story:** As a planner looking at an empty column, I want an "Add task" affordance right there, so I don't have to go find another entry point just because the column happens to be empty.
**Acceptance criteria:**
- An empty Day Board column (agent has no timeline, or a timeline with zero tasks, for `activeDay`) renders an "Add task" row in the same location/style a populated column would show its task list.
- Clicking it opens the same task-creation flow used elsewhere (reuse existing handlers — don't build a parallel one).

### Story E3: Task edit via card click only; menu reorder actions
**Status:** ⬜ Not started
**Short description:** Standardize task editing to "click the card" everywhere (matching the Backlog Drawer's existing pattern), and consolidate the remaining per-task actions into the "…" menu, adding non-drag reordering.
**User story:** As a planner, I want one consistent way to open a task for editing (click it) and a predictable menu for everything else, so I'm not guessing whether a click, a hidden button, or a menu item does what I want.
**Acceptance criteria:**
- On Day Board / timeline task cards, clicking the card opens the task edit modal — this must be the *only* way to open it from a task card (remove any separate "Edit" button/menu-item if one exists there, mirroring what Backlog rows already do).
- The "…" menu on timeline task cards keeps: Move (to another agent/day), Return to backlog, Delete.
- The "…" menu gains: Move up, Move down — non-drag reordering that swaps the task's position with its immediate neighbor in `seq` order and re-triggers `recomputeTimeline` so times cascade correctly afterward. Disable "Move up" on the first task and "Move down" on the last.

---

## Epic F — Date Range Controls

### Story F1: Keep week toggle; add paging
**Status:** ⬜ Not started
**Short description:** The audit explicitly says to *keep* the existing 1-week/2-week toggle, but add `‹ ›` paging when in 1-week mode.
**User story:** As a planner viewing one week at a time, I want to page forward/back a week, so I can move through the whole planning window without switching to 2-week view.
**Acceptance criteria:**
- 1-week / 2-week toggle is unchanged in behavior.
- In 1-week mode, `‹` and `›` paging controls appear and move the visible range back/forward by 7 days.
- Both paging controls are disabled (not hidden) when paging would move outside the workspace's `planningWindowStart` / `planningWindowEnd`.
- Paging in 2-week mode is out of scope (the audit only calls for it in 1-week mode) unless the user says otherwise.

---

## Epic G — Publish Confirmation & Failure Handling

### Story G1: Keep single-timeline publish confirmation
**Status:** ⬜ Not started / not verified — check if this already exists in the current codebase before writing new code.
**Short description:** The audit says to explicitly *keep* a one-sentence confirmation before a single-timeline Publish, because publish triggers real downstream execution.
**User story:** As a planner about to publish a plan, I want a one-sentence confirmation naming who it goes to, so I don't accidentally trigger real-world execution with a stray click.
**Acceptance criteria:**
- Clicking Publish on a single timeline shows a confirmation step with one sentence in the form: "Publishing sends this plan to {agent name} for execution." (dynamically insert the timeline's assigned agent name — the audit's example used "Kavita" because that was the agent being published in the example, not a hardcoded name).
- Confirming proceeds with the existing publish flow (through `getTimelineReadiness` guard, etc.) — don't change the underlying publish logic, only the confirmation step.
- "Publish day" (bulk publish) confirmation behavior is unaffected by this story unless Story G2 says otherwise.

### Story G2: Publish failure / retry state
**Status:** 🚫 **Blocked — spec incomplete.** The addendum text cut off mid-sentence after: *"Publishing copies the plan to the execution system and can fail. Design a column-header state: 'Publish failed' + a one-line reason + a 'Retry' button. The timeline stays in draft, unlocked, until a publish succeeds. Publish day's..."* — the rest of this item (clearly about how bulk "Publish day" should behave with per-timeline failures) was never received.
**Action:** Do not implement this story from guesswork. Ask the user to supply the rest of item 20's text, specifically how "Publish day" (the bulk publish across a column of agents) should behave when one or more individual timeline publishes fail — e.g. does it publish the successes and only show failures for the failed ones, does it roll back everything, etc.
**Partial acceptance criteria (known-good, safe to build once unblocked):**
- A timeline whose publish attempt fails shows a column-header state: "Publish failed" + a one-line failure reason + a "Retry" button.
- A failed timeline stays in draft and unlocked (fully editable) until a subsequent publish succeeds — it must never be left in a half-published/locked limbo state.

---

## Epic H — Bug Fixes (Batch E)

**Status:** 🚫 **Blocked — spec never received.** The original audit addendum's items 21–27 (described only as "Batch E: bugs") were never provided in full — only the category label survived. Do not invent bug reports. Ask the user to supply the complete text for items 21 through 27 before starting this epic.

---

## How to use this prompt

1. Read the Context section above and skim the actual current state of `AgentRosterRail.tsx`, `BacklogDrawer.tsx`, `ScheduleGrid.tsx`, and `DayBoard.tsx` before writing anything — some items may already be partially implemented depending on what state the code was in when it was exported to this repo. Don't assume "Not started" stories are truly untouched; verify against the acceptance criteria first.
2. Work Epic B → C → D → E → F → G in order (skip G2 and Epic H until their specs are supplied).
3. After each story, run the dev server and manually verify every acceptance criterion before starting the next story.
4. For G2 and Epic H: stop and ask the user for the missing text rather than guessing.
