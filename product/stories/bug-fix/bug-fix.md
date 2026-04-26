 Bug Fix Stories

---

## BUG-01 — Journey map rename reverts to "Untitled Journey Map"

**Date:** 2026-04-16
**Status:** ✅ FIXED
**File:** `webapp/protype-2/src/xano.ts`
**Discovered via:** Manual UI test — typing a new map name on the dashboard tile and pressing Enter

---

### 🐛 Symptom

When a user renames a journey map from the dashboard (e.g. changing "Untitled Journey Map" to "Pizza Delivery"), the tile briefly shows the new name then immediately snaps back to the old name. No error message is shown.

---

### 🔍 Root Cause

`updateJourneyMapMeta` in `xano.ts` was calling `PUT /journey_map/{id}` instead of `PATCH /journey_map/{id}`.

These are two **different backend endpoints** with fundamentally different semantics:

| Verb | API file | Backend op | Behaviour |
|------|----------|------------|-----------|
| `PUT` | `20_journey_map_journey_map_id_PUT.xs` | `db.edit` | **Full replace** — every column must be supplied |
| `PATCH` | `21_journey_map_journey_map_id_PATCH.xs` | `db.patch` | **Partial update** — only keys present in the request body are touched |

The frontend only sent `{ title: "Pizza Delivery" }`. The `PUT` handler passed `null` for every unsent column — including `owner_user` (a required foreign key to the `user` table). The database rejected the write with a constraint violation, causing the API to return an error.

Back in `Dashboard.tsx`, `handleRename` catches any API error and restores the previous map record from its `prev` snapshot — silently reverting the title to "Untitled Journey Map":

```ts
} catch {
  if (prev) setMaps((ms) => ms.map((m) => (m.id === id ? prev : m)));
}
```

The same bug also affected archive/unarchive (`handleArchive`) because it calls the same `updateJourneyMapMeta` with `{ status: next }`.

---

### 🗺️ Story

> **As a user**, I want to rename a journey map from the dashboard tile so that my map list stays organised.

**Acceptance Criteria (from US-DASH-06):**
- `PATCH /journey_map/{id}` is called with only the changed field (`title`).
- The tile updates optimistically and **stays updated** after the API call succeeds.
- On API failure the tile reverts and shows an error (existing revert logic is intentional for real errors).
- Archive/unarchive (`{ status: next }`) works via the same function.

---

### 🔧 Fix

**One-line change** in `webapp/protype-2/src/xano.ts`:

```ts
// BEFORE (broken) — full replace, nulls out every unsent column
return xanoRequest<XanoJourneyMap>(`/journey_map/${journeyMapId}`, {method: 'PUT', body: data});

// AFTER (correct) — partial update, only touches the fields in the body
return xanoRequest<XanoJourneyMap>(`/journey_map/${journeyMapId}`, {method: 'PATCH', body: data});
```

The PATCH endpoint uses `$input|pick:($raw_input|keys)|filter_null|filter_empty_text`, so only the keys present in the request body are written to the database. `owner_user`, `account_id`, and all other columns remain untouched.

---

### ✅ Verification

1. Open the dashboard.
2. Click the kebab menu on any map tile → **Rename**.
3. Type "Pizza Delivery" → press **Enter**.
4. The tile should show "Pizza Delivery" and **not revert**.
5. Reload the page — the new name should persist.
6. Repeat for archive/unarchive to confirm `status` updates also stick.

---

## BUG-02 — AI agent adds lenses with blank actor identity and no actor_fields scaffold on cells

**Date:** 2026-04-16
**Status:** ✅ FIXED
**Files:** `tools/7_scaffold_structure.xs`, `tools/4_mutate_structure.xs`
**Discovered via:** Code audit — comparing AI tool lens-add paths against the `journey_lens/add` API

---

### 🐛 Symptom

When the AI agent adds a new lens row during a build session (via `scaffold_structure` or `mutate_structure`), the resulting lens has:
- `actor_type` = `""`
- `template_key` = `""`
- `role_prompt` = `""`

And every cell created for that lens has `actor_fields = null` — meaning the structured template fields (e.g. `entry_trigger`, `emotions`, `friction_points` for a customer row) are never scaffolded. The agent then has no named fields to target with `update_actor_cell_fields`, and the Cell Detail Panel shows nothing.

---

### 🔍 Root Cause

The AI agent tools bypass the `journey_lens/add` API endpoint (`49_journey_lens_add_journey_map_id_POST.xs`) because `api.call` inside a tool does not forward the authenticated user context, so the auth-protected endpoint would reject it. Instead, both tools write directly to the DB — but they were written before the actor template system existed, so they hardcode empty strings and omit `actor_fields` entirely.

**In `tools/7_scaffold_structure.xs` (lens add path):**
```xs
db.add journey_lens {
  data = {
    actor_type   : ""   // ← hardcoded blank
    template_key : ""   // ← hardcoded blank
    role_prompt  : ""   // ← hardcoded blank
  }
}
db.add journey_cell {
  data = {
    content  : ""
    // actor_fields never written
  }
}
```

**In `tools/4_mutate_structure.xs` (add_lens action):**
Identical pattern — same three hardcoded empty strings, same missing `actor_fields` on cells.

Additionally, neither tool accepts `actor_type` as an input, so the agent had no way to pass the actor type even if the logic existed.

---

### 🗺️ Story

> **As a PM using the AI assistant**, I want actor lens rows added by the AI agent to carry the correct template identity and structured cell fields, so that the agent can immediately populate named fields like `emotions`, `entry_trigger`, and `friction_points` without any manual setup.

**Acceptance Criteria:**
- `scaffold_structure` lens_operations `add` items accept an optional `actor_type` field.
- `mutate_structure` `add_lens` action accepts an optional `actor_type` input.
- When `actor_type` is provided, the lens is created with the correct `template_key` and `role_prompt` derived from the actor template registry.
- Each cell created for the new lens has `actor_fields` pre-scaffolded with the correct null-keyed structure for the actor type.
- When `actor_type` is omitted, behaviour is unchanged (blank identity, null `actor_fields`).

---

### 🔧 Fix

**`tools/7_scaffold_structure.xs`** — In the lens `add` pass, extract `$op.actor_type`, apply the full template conditional block (matching the `journey_lens/add` API logic) to derive `$sc_template_key`, `$sc_role_prompt`, and `$sc_actor_fields_scaffold`. Pass all three to `db.add journey_lens` and pass `actor_fields: $sc_actor_fields_scaffold` to each `db.add journey_cell`. Updated instructions to document `actor_type` as an optional field in lens_operations add items.

**`tools/4_mutate_structure.xs`** — Added `text actor_type? filters=trim` to the tool input. In the `add_lens` branch, apply the same template block to derive the three scaffold vars. Pass them to the lens and cell DB writes. Updated instructions to document the new `actor_type` parameter.

---

### ✅ Verification

1. Start a new conversation with the Journey Map Assistant on a fresh draft map.
2. Instruct the agent: *"Add a Customer row"*.
3. In Xano, inspect the created `journey_lens` record — `actor_type` should be `customer`, `template_key` should be `customer-v1`, `role_prompt` should contain the full customer prompt.
4. Inspect the created `journey_cell` records for that lens — `actor_fields` should be `{ entry_trigger: null, emotions: null, information_needs: null, decisions_required: null, friction_points: null, assumptions: null, acceptance_criteria: null, expected_output: null, channel_touchpoint: null }`.
5. Ask the agent to fill in the customer perspective — it should call `update_actor_cell_fields` with named fields, not fall back to `update_cell`.
6. Repeat steps 2–5 with `internal`, `engineering`, `ai_agent`, `handoff`, and `vendor` actor types.

---

## BUG-03 — Adding a new stage creates cells for actor lenses without actor_fields scaffold

**Date:** 2026-04-16
**Status:** ✅ FIXED
**File:** `apis/journey_map/47_journey_stage_add_journey_map_id_POST.xs`
**Discovered via:** Code audit — BUG-02 review revealed the same gap in the stage-add path

---

### 🐛 Symptom

When a new stage (column) is added to a map that already has actor lens rows, every cell created for that new stage has `actor_fields = null` — even for lenses with a known `template_key` like `customer-v1`. The Cell Detail Panel for those cells shows no structured fields, and the agent cannot write to named actor fields until a workaround is applied.

---

### 🔍 Root Cause

`47_journey_stage_add_journey_map_id_POST.xs` loops over `$existing_lenses` and creates one cell per lens, but it only writes `content`, `status`, and `is_locked` — it never reads `lens.template_key` to derive and scaffold `actor_fields`.

```xs
foreach ($existing_lenses) {
  each as $lens {
    db.add journey_cell {
      data = {
        content  : ""
        status   : "open"
        is_locked: false
        // actor_fields never written — bug
      }
    }
  }
}
```

---

### 🗺️ Story

> **As a PM**, I want every cell created when I add a new stage to be pre-scaffolded with the correct actor fields for that row's template, so that I don't have to do manual setup before the AI agent can fill structured data.

**Acceptance Criteria:**
- When a new stage is added to a map with actor lenses, each resulting cell for an actor lens has `actor_fields` scaffolded from the lens's `template_key`.
- Lenses with no `template_key` (e.g. the default Description row) get `actor_fields: null` as before.
- All supported template keys are covered: `customer-v1`, `internal-v1`, `engineering-v1`, `ai-agent-v1`, `handoff-v1`, `vendor-v1`.

---

### 🔧 Fix

**`apis/journey_map/47_journey_stage_add_journey_map_id_POST.xs`** — Inside the foreach over `$existing_lenses`, added a per-lens block that derives `$cell_actor_fields_scaffold` from `$lens.template_key` using the same conditional structure as the `journey_lens/add` API. Passes `actor_fields: $cell_actor_fields_scaffold` to each `db.add journey_cell`.

---

### ✅ Verification

1. Open a map that has at least one Customer actor row (with `template_key = customer-v1`).
2. Add a new stage via the UI or the AI agent.
3. Inspect the newly created `journey_cell` records for the Customer lens — `actor_fields` should contain the 9-key customer scaffold.
4. Repeat for maps with Internal, Engineering, AI Agent, Handoff, and Vendor lenses.
5. Confirm the Description row cell still has `actor_fields = null`.

---

## BUG-04 — Post-login redirect lands on Journey Maps instead of Journey Architectures

**Date:** 2026-04-20
**Status:** ✅ FIXED
**Files:** `webapp/protype-2/src/main.tsx`, `webapp/protype-2/src/Login.tsx`
**Branch:** `BUG-04-post-login-redirect-architectures`
**Discovered via:** Manual UI test — signing in and observing landing page

---

### 🐛 Symptom

After signing in, the user is taken to `/dashboard` (the **Journey Maps** tile view) which shows a single "Untitled Journey Map" orphan. The expected flow is to land on `/architectures` first, pick "White Glove Online Last Mile Delivery Washer & Dryer", then see the correct "test 1" and "test 2" journey maps scoped to that architecture.

Additionally, navigating to `/architectures` then back works correctly — proving the data and architecture scope are fine — so the bug is purely in the post-login redirect destination.

---

### 🔍 Root Cause

Three hardcoded `/dashboard` references send authenticated users to the wrong page:

| File | Location | Default |
|------|----------|---------|
| `main.tsx` | `PublicRoute` — already-auth'd users bounced away from `/login` | `<Navigate to="/dashboard" />` |
| `main.tsx` | Catch-all `*` route | `<Navigate to="/dashboard" />` |
| `Login.tsx` | `from` fallback when no redirect state is present | `?? '/dashboard'` |

`/dashboard` renders `Dashboard.tsx` which calls `GET /journey_map` and filters to **standalone maps only** (`!m.journey_architecture`). The "Untitled Journey Map" shown is a real orphan record that has no `journey_architecture` FK — it is correctly excluded from the Architecture view. "test 1" and "test 2" belong to the "White Glove" architecture and are therefore invisible on this page.

The user's mental model is **Architecture → Journey Map**, so the entry point should be `/architectures`.

---

### 🗺️ Story

> **As a returning user**, I want to land on the Journey Architectures page after signing in, so that I can immediately select the correct architecture and see its associated journey maps.

**Acceptance Criteria:**
- After a successful sign-in, the browser navigates to `/architectures`.
- Authenticated users who hit `/login` directly are also bounced to `/architectures`.
- Any unknown URL still redirects authenticated users to `/architectures`.
- The `/dashboard` (standalone maps) page remains accessible via the "Journey Maps" nav link.

---

### 🔧 Fix

**`webapp/protype-2/src/main.tsx`** — Two changes:

```tsx
// BEFORE — PublicRoute
if (user) return <Navigate to="/dashboard" replace />;

// AFTER
if (user) return <Navigate to="/architectures" replace />;

// BEFORE — catch-all
<Route path="*" element={<Navigate to="/dashboard" replace />} />

// AFTER
<Route path="*" element={<Navigate to="/architectures" replace />} />
```

**`webapp/protype-2/src/Login.tsx`** — One change:

```tsx
// BEFORE
const from = (location.state as { from?: { pathname: string } })?.from?.pathname ?? '/dashboard';

// AFTER
const from = (location.state as { from?: { pathname: string } })?.from?.pathname ?? '/architectures';
```

---

### ✅ Verification

1. Sign out if currently logged in.
2. Navigate to `http://localhost:5173` — should redirect to `/login`.
3. Sign in with valid credentials.
4. Browser should land on `/architectures` showing "White Glove Online Last Mile Delivery Washer & Dryer".
5. Click that architecture tile → should see "test 1" and "test 2".
6. Sign out, navigate directly to `http://localhost:5173/login`, sign in again — confirm same landing page.
7. Confirm `/dashboard` is still reachable via the "Journey Maps" nav link inside the Architectures header.

---

## BUG-05 — Stale "← Journey Maps" back button on Journey Architectures page

**Date:** 2026-04-20
**Status:** ✅ FIXED
**File:** `webapp/protype-2/src/ArchitectureDashboard.tsx`
**Branch:** `BUG-05-remove-journey-maps-back-button`
**Discovered via:** Manual UI review — unexpected back button visible on `/architectures`

---

### 🐛 Symptom

The Journey Architectures page (`/architectures`) shows a `← Journey Maps` back button in the top-left header. Clicking it navigates to `/dashboard`, which displays only orphan (standalone) journey maps — not the maps associated with any architecture. This is confusing because the user's mental model expects:

- **Architectures page** = top-level home
- **Click an architecture tile** = see its associated journey maps

A back button implying a parent above Architectures contradicts that model.

---

### 🔍 Root Cause

`ArchitectureDashboard.tsx` still contains a header button left over from before BUG-04, when `/dashboard` was the application entry point and Architectures was a sub-section beneath it:

```tsx
<button onClick={() => navigate('/dashboard')} className="...">
  <ArrowLeft className="w-3.5 h-3.5" /><span className="font-medium">Journey Maps</span>
</button>
```

After BUG-04 made `/architectures` the entry point, this button became orphaned — it points to a page that is no longer a logical parent of Architectures.

---

### 🗺️ Story

> **As a user**, I want the Journey Architectures page to feel like the top-level home so that the navigation hierarchy is clear and I am not misled by a back button that goes nowhere meaningful.

**Acceptance Criteria:**
- The `← Journey Maps` back button is removed from the `/architectures` header.
- The Architectures page has no back navigation (it is the root).
- `/dashboard` remains reachable via any existing internal link (e.g. from the map editor).

---

### 🔧 Fix

**`webapp/protype-2/src/ArchitectureDashboard.tsx`** — Remove the back button and its surrounding divider from the header:

```tsx
// REMOVE these elements from the header
<button onClick={() => navigate('/dashboard')} className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-800 transition-colors">
  <ArrowLeft className="w-3.5 h-3.5" /><span className="font-medium">Journey Maps</span>
</button>
<div className="w-px h-4 bg-zinc-200" />
```

---

### ✅ Verification

1. Navigate to `/architectures`.
2. Confirm there is **no** `← Journey Maps` button in the top-left header.
3. Confirm the Architectures title and "A" icon are still visible.
4. Confirm clicking an architecture tile navigates to its detail page with associated maps.
5. Confirm `/dashboard` is still reachable from the map editor back button (for orphan maps).

---

## BUG-06 — `get_gaps` ignores `actor_fields` — AI reports 0 gaps on maps with empty actor rows

**Date:** 2026-04-22
**Status:** 🔧 FIXED
**File:** `tools/9_get_gaps.xs`
**Discovered via:** AI chatbot reporting "Map complete — 0 gaps" while actor rows (Customer, Driver, Support Agent) were visibly empty in the UI.

---

### 🐛 Symptom

After the AI builds a journey map the agent calls `get_gaps`, receives `total_gaps: 0`, and declares the map complete. The matrix UI still shows `No data yet` on every actor lens row.

---

### 🔍 Root Cause

`get_gaps` evaluates emptiness using only the `content` field:

```
if ($c.content == null || $c.content == "") { // gap }
```

Actor lens cells (Customer, Driver, Support Agent, etc.) store their data in `actor_fields` (a JSON column), not in `content`. The Description row uses `content`. So:

| Row type | Data stored in | Checked by get_gaps |
|---|---|---|
| Description | `content` | ✅ Yes |
| Actor (Customer, Driver…) | `actor_fields` | ❌ No |

When actor cells are scaffolded at creation time they receive `actor_fields: {emotions: null, entry_trigger: null, ...}` — a non-null object with all-null values. The gap check only tested `actor_fields == null`, so these cells passed as filled even though every sub-field was empty. The AI called `get_gaps`, got `0 gaps`, and declared the map complete while the matrix showed "No data yet" on every actor row.

---

### ✅ Fix

Add a secondary emptiness check: a cell is also a gap if it belongs to an actor lens (`actor_type` is not null/empty) **and** `actor_fields` is null or an empty object.

**File:** `tools/9_get_gaps.xs`

Change the gap condition from:
```
if ($c.content == null || $c.content == "")
```
To:
```
if (
  ($c.content == null || $c.content == "") &&
  ($c.actor_type == null || $c.actor_type == "")
) OR (
  ($c.actor_type != null && $c.actor_type != "") &&
  ($c.actor_fields == null || $c.actor_fields == {})
)
```

---

### ✅ Verification

1. Create a map with at least one Description row and one actor row (e.g. Customer).
2. Fill only the Description cells — leave actor cells empty.
3. Call `get_gaps` — confirm it returns gaps for the empty actor cells.
4. Fill the actor cells via `update_actor_cell_fields`.
5. Call `get_gaps` again — confirm `total_gaps: 0`.

---

## BUG-07 — `cell_updates` response never includes actor field writes — UI stays stale

**Date:** 2026-04-22
**Status:** 🔧 FIXED
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
**Discovered via:** AI reporting "32 cells filled" but matrix showing "No data yet" on all actor rows after confirmed DB writes.

### 🐛 Symptom

After the AI calls `update_actor_cell_fields`, the matrix UI shows "No data yet" on every actor row even though the data is in the database. A page refresh reveals the filled content.

### 🔍 Root Cause

The post-turn change detection in `52_...ai_message_POST.xs` builds `$cell_updates` by comparing only the `content` field:

```
if ($uc.content != $orig_content)  // actor_fields never compared
```

`update_actor_cell_fields` writes to `actor_fields`, not `content`. So actor writes produce zero entries in `cell_updates`. The frontend only applies what's in `cell_updates` — it never learns about actor field writes and local state stays stale.

### ✅ Fix

- Build a pre-turn snapshot of `actor_fields` alongside `content`
- In the post-turn diff loop, also detect `actor_fields` changes
- Include `actor_fields` in the `cell_updates` payload items

---

## BUG-08 — Progress percentage ignores actor field cells — build loop never completes

**Date:** 2026-04-22
**Status:** 🔧 FIXED
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
**Discovered via:** Build loop stalling at ~14% despite actor cells being written.

### 🐛 Symptom

The build loop's auto-continuation checks `progress.percentage >= 95`. Progress never reaches 95% on maps with actor rows — it stays stuck around 14% (only description cells count). The loop stalls via the zero-write detection instead of completing cleanly.

### 🔍 Root Cause

The progress calculation only counts cells where `content` is non-null:

```
if ($fc.content != null && $fc.content != "")  // actor cells never counted
```

Actor cells are filled via `actor_fields`, not `content`. They are always counted as empty regardless of how many fields were written.

### ✅ Fix

Mirror the same `is_actor_lens` + all-null-values check from BUG-06 in the progress calculation loop so that actor cells with at least one non-null `actor_fields` value count as filled.

---

## BUG-09 — Frontend `AiCellUpdate` type and `setCells` handler ignore `actor_fields`

**Date:** 2026-04-22
**Status:** 🔧 FIXED
**Files:** `webapp/protype-2/src/xano.ts`, `webapp/protype-2/src/App.tsx`
**Discovered via:** Actor fields written and returned in `cell_updates` not reflected in local React state.

### 🐛 Symptom

Even after BUG-07 is fixed (backend sends `actor_fields` in `cell_updates`), the matrix UI would still not update because the frontend discards the field.

### 🔍 Root Cause

`AiCellUpdate` in `xano.ts` has no `actor_fields` property. The `setCells` update in `App.tsx` only maps `content`, `status`, `isLocked` — `actorFields` is never updated from AI responses.

### ✅ Fix

- Add `actor_fields?: Record<string, string | null> | null` to `AiCellUpdate` in `xano.ts`
- In the `setCells` callback in `App.tsx`, apply `actorFields: update.actor_fields ?? cell.actorFields`

---

## BUG-10 — Journey Health widget shows "No metrics yet" even when Metrics lens row is populated

**Date:** 2026-04-22
**Status:** 🔧 FIXED
**File:** `apis/journey_map/75_journey_map_journey_map_id_scorecard_GET.xs`
**Discovered via:** Manual UI review — Journey Health panel empty on "Last-mile Happy Path" map despite Metrics row visibly showing health scores and completion rates.

---

### 🐛 Symptom

The Journey Health side panel displays "No metrics yet — add a Metrics lens row to enable" even though the Metrics lens row is present and fully populated with `stage_health`, `completion_rate`, `drop_off_rate`, etc. The Financial Intelligence lens renders correctly in the same map.

---

### 🔍 Root Cause

The scorecard API finds the metrics lens by `template_key == "metrics-v1"`:

```xs
db.query journey_lens {
  where = $db.journey_lens.journey_map == $input.journey_map_id
       && $db.journey_lens.template_key == "metrics-v1"
  return = {type: "single"}
} as $metrics_lens
```

If `$metrics_lens` is null, the entire per-stage metrics block is skipped and `$populated_count` stays 0. The widget then sees `populated_count === 0` and renders the empty state.

The Metrics lens in the affected map was created without `template_key = "metrics-v1"` (e.g. added manually or via an older flow). The matrix renders fine because the frontend reads `actor_fields` directly from cells — it never uses the scorecard. Journey Health is the only thing gated on `template_key`.

---

### 🗺️ Story

> **As a PM**, I want the Journey Health panel to populate whenever a Metrics lens row exists and has data, regardless of how or when the row was created, so that scorecard values are always visible.

**Acceptance Criteria:**
- If a lens with `template_key = "metrics-v1"` exists, the scorecard uses it (existing behaviour, unchanged).
- If no `template_key` match is found but a lens with `actor_type = "metrics"` exists, the scorecard falls back to that lens.
- Journey Health panel shows health scores, critical stage count, and revenue at risk whenever any metrics-type lens has populated cells.
- Maps with no metrics lens at all still show the empty state.

---

### 🔧 Fix

**`apis/journey_map/75_journey_map_journey_map_id_scorecard_GET.xs`** — After the `template_key` query, add a conditional fallback that queries by `actor_type == "metrics"` when `$metrics_lens` is null:

```xs
conditional {
  if ($metrics_lens == null) {
    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.journey_map_id
           && $db.journey_lens.actor_type == "metrics"
      return = {type: "single"}
    } as $metrics_lens
  }
}
```

---

### ✅ Verification

1. Open a journey map whose Metrics lens was created without `template_key = "metrics-v1"` (e.g. "Last-mile Happy Path").
2. Open the Journey Health side panel — it should now show the health score, critical stage count, and any revenue-at-risk values.
3. Confirm maps with a properly-keyed `metrics-v1` lens are unaffected.
4. Create a brand-new map with no Metrics row — panel should still show the empty state.
