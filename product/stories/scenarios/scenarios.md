# Epic: Journey Map Scenarios

## Purpose

Give users a structured "what if" workspace inside a Journey Architecture. A scenario is a journey map that lives inside an architecture — users clone the current map, make one change, and compare outcomes side-by-side against another scenario to decide which configuration actually improves journey health.

## The Flow

```
Journey Architecture detail
  → Scenarios tab
    → List: Name | Owner | Created | Last Modified | ...
      → Create Scenario modal (Clone or Blank) → opens journey map editor
      → Click scenario name → opens journey map editor
      → Select 2 scenarios → Compare button activates → Compare Health view
        → Side-by-side metrics, color-coded, Open Journey buttons
        → < Scenarios breadcrumb → back to list
      → ... menu → Rename | Duplicate | Delete
      → Search → filters list live
```

## Color Logic (Compare Health)

Green = this scenario **wins** this metric vs the other. Red = this scenario **loses**. Black = tied or structural (no winner declared).

| Metric | Green when |
|---|---|
| Journey Health Score | Higher |
| Stage Health (per stage row) | Higher |
| Revenue at Risk | Lower |
| Critical Stages count | Fewer |

## Data Model Note

No new table needed. Scenarios **are** journey maps with a non-null `journey_architecture` FK. One new nullable field is added to `journey_map` for lineage tracking.

---

## Backend Stories

---

### US-SCN-01 — DB: add `cloned_from_map_id` to `journey_map`

**Story:** As a backend engineer, I want a nullable self-referencing FK on `journey_map` so that cloned scenarios record which map they were copied from, enabling future diff and lineage features.

**Migration: `journey_map` table**
- Add nullable field: `cloned_from_map_id` (int → `journey_map`)
- Existing maps with `null` are unaffected

**Acceptance Criteria:**
- [ ] Field added to `tables/6_journey_map.xs` with nullable FK referencing `journey_map`
- [ ] Existing maps unaffected — field is `null` by default
- [ ] All existing workflow tests continue to pass

---

### US-SCN-02 — `GET /journey_architecture/{id}/scenarios`

**Story:** As an authenticated user, I want to list all journey maps within a Journey Architecture so that I can browse, search, and select scenarios to open or compare.

**Auth:** `auth = "user"` — verify requesting user owns the architecture before returning data.

**Query:** All `journey_map` records where `journey_architecture = {id}`, ordered by `updated_at DESC`.

**Response shape:**
```json
[
  {
    "id": 42,
    "title": "Baseline — Checkout Journey",
    "owner_name": "javier",
    "created_at": "2026-04-02T10:00:00Z",
    "updated_at": "2026-04-14T15:30:00Z",
    "cloned_from_map_id": null
  }
]
```

**Acceptance Criteria:**
- [ ] Returns only maps belonging to the given architecture `id`
- [ ] Returns `403` if requesting user does not own the architecture
- [ ] Returns `[]` (not 404) when no scenarios exist yet
- [ ] `owner_name` is resolved via join on the `user` table (display name or email)
- [ ] Results ordered by `updated_at DESC`

---

### US-SCN-03 — `POST /journey_architecture/{id}/scenarios/clone`

**Story:** As an authenticated user, I want to deep-clone an existing scenario so that I can make a single targeted change without touching the original map.

**Input:**
```json
{ "source_map_id": 42, "title": "Fix Stage 3 Handoff" }
```
- `title` optional — defaults to `"Copy of {source title}"`

**Clone logic (execute in order):**
1. Copy `journey_map` record → set `journey_architecture = {id}`, `owner_user = $auth.id`, `cloned_from_map_id = source_map_id`, fresh `created_at`/`updated_at`, reset all journey settings fields to null
2. For each `journey_stage` in source map → copy to new map (preserve `label`, `position`)
3. For each `journey_lens` in source map → copy to new map (preserve `actor_type`, `template_key`, `role_prompt`, `label`)
4. For each `journey_cell` in source map → copy to new map (preserve `content`, `status`, `actor_fields`), set `is_locked = false`

**Response:** Full new journey map object (same shape as the US-SCN-02 list item).

**Explicitly NOT cloned (clean slate):**
- `journey_link` records — a scenario is standalone; graph topology does not carry over
- `agent_conversation` / `agent_message` records — clone starts with no AI history

**Acceptance Criteria:**
- [ ] New map has all stages, lenses, and cells copied from source
- [ ] `cloned_from_map_id` set to `source_map_id` on the new map
- [ ] Source map is completely unchanged after clone
- [ ] Returns `403` if `source_map_id` does not belong to the given architecture
- [ ] Returns `404` if `source_map_id` does not exist
- [ ] Default title applied when none provided: `"Copy of {source title}"`
- [ ] `is_locked` on all cloned cells is reset to `false`
- [ ] No journey links are copied — the clone has zero links on creation
- [ ] No agent conversations are copied — clone starts with a clean AI slate
- [ ] `settings` and `smart_ai_settings` on the new map are `null` (reset)

---

### US-SCN-04 — `GET /journey_architecture/{id}/compare`

**Story:** As an authenticated user, I want to compare the health scorecard of two scenarios side-by-side so that I can see which configuration produces better journey outcomes.

**Query params:** `?map_a={id}&map_b={id}` (both required)

**Auth:** `auth = "user"` — verify both maps belong to the architecture and the user owns the architecture.

**Logic:**
- For each map: fetch the same scorecard data as `GET /journey_map/{id}/scorecard` (Journey Health, Revenue at Risk, Critical Stages, per-stage breakdown)
- Return both raw — frontend computes relative color labels

**Response shape:**
```json
{
  "map_a": {
    "id": 42,
    "title": "Fix Stage 3 Handoff",
    "journey_health": 7.2,
    "revenue_at_risk": 71000,
    "critical_stages": 2,
    "stage_breakdown": [
      { "stage_label": "Checkout", "stage_health": 6.8 },
      { "stage_label": "Fulfillment", "stage_health": 5.2 }
    ]
  },
  "map_b": {
    "id": 43,
    "title": "Remove Friction Step",
    "journey_health": 8.4,
    "revenue_at_risk": 52000,
    "critical_stages": 0,
    "stage_breakdown": [
      { "stage_label": "Checkout", "stage_health": 8.1 },
      { "stage_label": "Fulfillment", "stage_health": 7.0 }
    ]
  }
}
```

**Stage mismatch rule:** Two scenarios cloned from the same source will always have matching stages. If stages differ (e.g. a stage was added/deleted post-clone), align by `stage_key` — stages present in one but not the other return `null` health for the missing side.

**Compare URL:** Rendered as a sub-state of the architecture detail page at `/architectures/{id}?tab=scenarios&comparing={mapA},{mapB}` — this makes it bookmarkable and browser-back-safe.

**Acceptance Criteria:**
- [ ] Returns `400` if either `map_a` or `map_b` param is missing
- [ ] Returns `403` if either map does not belong to the architecture or user doesn't own it
- [ ] Returns `400` if `map_a == map_b` (can't compare a map to itself)
- [ ] `null` returned for any metric where no data exists yet (same rules as scorecard endpoint)
- [ ] Stage breakdown arrays are ordered by stage position, not health score
- [ ] Stages present in one map but not the other are included with `null` health on the missing side

---

## Frontend Stories

---

### US-SCN-05 — Scenarios tab on Journey Architecture detail

**Story:** As a user viewing a Journey Architecture, I want a "Scenarios" tab so that I can access and manage all journey map variants from one place.

**Where it lives:** Journey Architecture detail page — add "Scenarios" as a tab alongside the existing map list or graph views.

**Tab label:** `Scenarios` with a count badge: `Scenarios (3)`

**Empty state (no maps in architecture yet):**
```
No scenarios yet
[ + Create your first scenario ]
```

**Acceptance Criteria:**
- [ ] Scenarios tab appears on the Journey Architecture detail page
- [ ] Tab count badge reflects current number of journey maps in the architecture
- [ ] Clicking the tab renders the Scenarios list view (US-SCN-06)
- [ ] Empty state shows when architecture has zero journey maps, with a Create link

---

### US-SCN-06 — Scenarios list view

**Story:** As a user on the Scenarios tab, I want to see a searchable table of scenarios with inline actions so that I can manage them without leaving the page.

**Toolbar — context-sensitive (no selection vs selection):**

Nothing selected:
```
[ + Create Scenario ]                                [ Search...  🔍 ]
```

1+ rows selected:
```
[ 🗑 Delete ]                                        [ Search...  🔍 ]
```

Exactly 2 rows selected:
```
[ Compare ]  [ 🗑 Delete ]                           [ Search...  🔍 ]
```

- `+ Create Scenario` is **hidden** whenever any checkbox is selected — prevents user from reading it as "create from selected"
- `Compare` appears **only** when exactly 2 rows are checked (not 1, not 3+)
- `🗑 Delete` appears whenever 1+ rows are checked; only succeeds for maps the current user owns

**Table columns:** `☐ | NAME | OWNER | CREATED | LAST MODIFIED | ...`
- `NAME` is a clickable link → opens the journey map editor for that scenario
- `...` kebab per row → `Duplicate | Rename | Delete`
- Clicking `Duplicate` calls US-SCN-03 clone endpoint with default title, then refreshes the list
- Clicking `Rename` opens a rename dialog (Scenario ID shown read-only, Scenario Name editable, Save / Cancel)
- Clicking `Delete` shows confirmation dialog — only succeeds if current user is owner

**Search:** Filters the list client-side on `title` as the user types. Shows "No results — clear search" state if nothing matches.

**Acceptance Criteria:**
- [ ] Table renders with all columns and correct data from US-SCN-02
- [ ] `+ Create Scenario` is visible only when no rows are selected
- [ ] Selecting 1+ rows hides `+ Create Scenario` and shows `🗑 Delete`
- [ ] Selecting exactly 2 rows shows both `Compare` and `🗑 Delete`; selecting any other count hides `Compare`
- [ ] Clicking a scenario name navigates to the journey map editor with that map loaded
- [ ] `...` menu shows Duplicate, Rename, Delete for every row
- [ ] Duplicate clones the scenario and inserts the new row at top of list
- [ ] Rename dialog saves via existing `PATCH /journey_map/{id}` endpoint
- [ ] Delete requires ownership; non-owner rows show an error toast if attempted
- [ ] Search filters visible rows live as user types; clearing search restores full list
- [ ] List re-fetches from US-SCN-02 after any create, clone, rename, or delete

---

### US-SCN-07 — Create Scenario modal

**Story:** As a user, I want a modal that lets me choose between cloning an existing scenario or starting blank so that the default path is always a controlled, comparable variant.

**Trigger:** `+ Create Scenario` button in the Scenarios list toolbar.

**Modal layout:**
```
┌──────────────────────────────────────────────┐
│  How would you like to create a scenario?    │
│                                              │
│  [ 🔄 ]                    [ + ]             │
│  Clone from an existing    Create a blank    │
│  scenario                  scenario          │
│                                              │
│  [Create Scenario]         [Create Scenario] │
└──────────────────────────────────────────────┘
```

**Clone path:**
- After clicking "Create Scenario" under Clone: show a picker dropdown of existing scenarios in this architecture, pre-selected to the most recently modified one
- Confirm → calls US-SCN-03 → navigates to the new map in the editor

**Blank path:**
- After clicking "Create Scenario" under Blank: calls existing `POST /journey_map` with `journey_architecture` set, default title `"Untitled Scenario"` → navigates to the new map in the editor

**Acceptance Criteria:**
- [ ] Modal opens on `+ Create Scenario` click
- [ ] Clone option shows a scenario picker populated from the architecture's maps
- [ ] Clone picker defaults to the most recently modified scenario
- [ ] Clone path calls US-SCN-03 and navigates to the new map on success
- [ ] Blank path creates a new bare journey map linked to the architecture and navigates to it
- [ ] Modal closes on Cancel or ESC without creating anything

---

### US-SCN-08 — Compare Health view

**Story:** As a user, I want to see two scenarios side-by-side with color-coded health metrics so that I can immediately tell which configuration is better and where the tradeoffs are.

**Trigger:** Select exactly 2 checkboxes in the Scenarios list → click `Compare`.

**Layout:**
```
< Scenarios  |  Compare Health (2)                 [ Export CSV ]
[ ▦ grid ] [ ☰ list ]

              Scenario A title          Scenario B title
              Last modified Apr 19      Last modified Apr 18

JOURNEY HEALTH     7.2 🔴                   8.4 🟢
STAGE: Awareness   8.1 ——                   8.1 ——   (tied → black)
STAGE: Checkout    6.8 🔴                   8.1 🟢
STAGE: Fulfillment 5.2 🔴                   7.0 🟢
REVENUE AT RISK    $71k 🔴                  $52k 🟢
CRITICAL STAGES    2 🔴                     0 🟢

              [ Open Journey ]          [ Open Journey ]
```

**Color logic (computed on frontend from US-SCN-04 response):**
- Per metric row: compare map_a value vs map_b value using the direction table in the epic header
- Winner → green text, Loser → red text, Tied (values equal) → black text
- `null` values → render `—` in black, no color applied

**Export CSV:** Downloads a flat CSV with scenario titles as column headers and all metrics as rows.

**Asymmetric metrics rule:** If one scenario has a real score and the other has `null`, the real score does NOT automatically win — `null` means "no data yet", not "zero". Both show their value with no color applied when one side is null.

**Both null state:** If all metrics are `null` for both scenarios, show an empty state nudge above the table: *"Fill in your scenarios with journey health data to compare them."*

**Acceptance Criteria:**
- [ ] Calls US-SCN-04 on load with the two selected map IDs
- [ ] Per-metric color applied correctly per the direction table (higher/lower wins)
- [ ] Tied values render in black — no green or red
- [ ] `null` metric values show `—` in black, no color even if the other side has a value
- [ ] Stage rows appear in stage position order (not sorted by health)
- [ ] Stages present in one map but missing in the other show `—` for the missing side
- [ ] `Open Journey` button navigates to that scenario's journey map editor
- [ ] Export CSV downloads with correct headers and values
- [ ] Grid/list toggle switches between card view and compact list view
- [ ] Empty state nudge shown when all metrics on both sides are `null`
- [ ] View is bookmarkable via `?tab=scenarios&comparing={a},{b}` URL param (US-SCN-04)

---

### US-SCN-09 — Navigation: back to Scenarios from editor and compare view

**Story:** As a user editing a scenario or viewing Compare Health, I want a clear way back to the Scenarios list so that I never lose my place in the workflow.

**From the journey map editor (when map belongs to an architecture):**
- Show a breadcrumb in the editor toolbar: `< Scenarios`
- Clicking it navigates back to the Scenarios tab of the parent architecture

**From the Compare Health view:**
- Breadcrumb: `< Scenarios | Compare Health (2)`
- Clicking `< Scenarios` navigates back to the Scenarios tab (checkboxes reset)

**From the journey map editor (opened via `Open Journey` in Compare view):**
- Breadcrumb: `< Scenarios` (same — navigate back to the Scenarios tab, not back to Compare)

**Acceptance Criteria:**
- [ ] Editor toolbar shows `< Scenarios` breadcrumb when `journey_architecture` is set on the map
- [ ] Clicking `< Scenarios` in the editor goes to the Scenarios tab of the correct architecture
- [ ] Compare Health shows breadcrumb `< Scenarios | Compare Health (2)`
- [ ] Clicking `< Scenarios` in Compare Health goes back to the Scenarios list with no selections active
- [ ] No breadcrumb shown in the editor for standalone maps (null `journey_architecture`)

---

### US-SCN-10 — Duplicate from Grid view

**Story:** As a user on the Grid view of a Journey Architecture, I want a Duplicate option in the map tile `...` menu so that I can create a scenario variant without switching to the Scenarios tab.

**Trigger:** `...` kebab on any map tile in Grid view → `Duplicate`

**Behaviour:**
- Calls US-SCN-03 clone endpoint with `source_map_id = map.id` and default title `"Copy of {title}"`
- New clone is inserted at top of the Grid and also visible in Scenarios tab immediately
- No modal — one-click, default title, navigate to the new map's editor after creation

**Acceptance Criteria:**
- [ ] `Duplicate` appears in the Grid view map tile `...` menu for every tile
- [ ] Clicking Duplicate calls the clone API and shows a loading state on the tile
- [ ] New clone appears at the top of the Grid on success
- [ ] Scenarios tab count badge increments correctly after Duplicate
- [ ] On failure, shows an error toast and leaves the grid unchanged

---

## Build Order

```
US-SCN-01 → US-SCN-02 → US-SCN-03 → US-SCN-04 → US-SCN-05 → US-SCN-06 → US-SCN-07 → US-SCN-08 → US-SCN-09
```

**Epic 1 — Data + list (shipped):**
`US-SCN-01` → `US-SCN-02` → `US-SCN-05` → `US-SCN-06` → `US-SCN-09`
*Bug fix in Epic 2: Scenarios tab count badge does not update when scenarios change inside ScenariosTab — fix via `onCountChange` callback.*

**Epic 2 — Create + CRUD:**
`US-SCN-03` (clone API) → `US-SCN-07` (create modal) → `US-SCN-10` (Grid Duplicate)
*Bug fix: `cloned_from_map_id === 0` rendered literal "0" text next to scenario names — React renders `{0 && <el />}` as `"0"`, not nothing. Xano returns `0` for unset nullable int fields instead of `null`. Fix: `{!!scenario.cloned_from_map_id && ...}`. UI only, no Xano changes. File: `ScenariosTab.tsx`.*

*Bug fix: Clone title computation caused `ERROR_FATAL: Not numeric` — xs `+` operator is numeric-only in API context (unlike tool context). Fix: removed all string concat from xs; title now composed on the frontend as `"Copy of {title}"` and passed as `input.title`. Backend falls back to `"Copy of Scenario"` only for direct API calls with no title. Files: `77_...clone_POST.xs`, `ArchitectureDetail.tsx`, `ScenariosTab.tsx`.*

**Epic 3 — Compare:**
`US-SCN-04` (compare API) → `US-SCN-08` (compare view)

## Explicit Non-Goals (this epic)

- Diff view ("what exactly changed between these two scenarios") — needs lineage data, deferred
- More than 2 scenarios in a single compare — color logic breaks with 3+
- JSON import/export of scenarios
- Sharing a scenario with another user who doesn't own the architecture
- Auto-declaring a "winner" — surface tradeoffs, let the PM decide
