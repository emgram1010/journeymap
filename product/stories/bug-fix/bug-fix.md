# Bug Fix Stories

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
