## Journey Settings Epic

### Purpose

Give every journey map a rich context layer — a set of structured fields that describe the journey before the matrix is even filled in. This context grounds the AI agent, helps stakeholders understand scope at a glance, and ensures the matrix is never built without a clear foundation.

### The 12 Fields

| # | Field | Definition | Example |
|---|---|---|---|
| 1 | Journey Name | What this journey is called | White Glove Appliance Delivery |
| 2 | Primary Actor | The main persona this journey is built around | Residential customer purchasing washer/dryer |
| 3 | Journey Scope | What is included and excluded | From order placement to delivery, excludes post-delivery support |
| 4 | Start Point | Where the journey begins | Customer places order online |
| 5 | End Point | Where the journey ends | Delivery completed and signed off |
| 6 | Duration | How long the entire journey typically takes | 7 to 14 days from order to delivery |
| 7 | Success Metrics | How success is measured overall | On-time delivery, satisfaction score above 4.5 stars |
| 8 | Key Stakeholders | All actors participating in the journey | Customer, route planner, driver, warehouse, AI system |
| 9 | Dependencies & Assumptions | External factors underpinning the journey | Inventory available, customer home during window |
| 10 | Pain Points Summary | High-level friction areas across the journey | Last-minute cancellations, address issues |
| 11 | Opportunities | Gaps or improvements identified | Better real-time tracking, predictive availability |
| 12 | Version / Last Updated | When the map was created or last reviewed | Version 2.1, updated April 2026 |

> **Note:** Journey Name already exists as `title` on the `journey_map` table. Fields 2–12 are new columns.

### Scope

- Backend schema additions to `journey_map` table
- A dedicated PATCH endpoint for saving journey settings
- Journey settings included in the load bundle response
- Frontend Journey Settings panel (sidebar or modal)
- Settings exposed as context to the AI agent

### Explicit non-goals

- Per-field access control or field-level locking
- Versioning history or change tracking for settings
- Exporting settings to PDF or external formats

---

### Epic: Journey Settings

---

**US-JS-01 — Add journey settings columns to the journey_map schema**

**Story:** As a product operator, I want the journey map record to store structured context fields so that every journey has a clear foundation before the matrix is filled in.

**Acceptance Criteria:**
- The following columns are added to the `journey_map` table, all optional text fields with `filters=trim`:
  - `primary_actor`, `journey_scope`, `start_point`, `end_point`, `duration`
  - `success_metrics`, `key_stakeholders`, `dependencies`, `pain_points_summary`
  - `opportunities`, `version`
- All fields are nullable — existing journey map records are unaffected
- `title` (Journey Name) already exists and requires no change

**Layer:** Backend — `tables/6_journey_map.xs`

---

**US-JS-02 — Expose journey settings in the load bundle API**

**Story:** As the frontend, I want the full journey settings to be returned when loading a journey map bundle so that the UI can display them without a separate API call.

**Acceptance Criteria:**
- The `journey_map/load_bundle/{journey_map_id}` response already returns the full `$journey_map` record
- All new settings fields are included automatically once the schema is updated
- No breaking change to the existing bundle response shape
- Frontend receives `null` for unpopulated settings fields

**Layer:** Backend — `apis/journey_map/43_journey_map_load_bundle_journey_map_id_GET.xs` (no change required if schema is updated correctly)

---

**US-JS-03 — Create a dedicated journey settings PATCH endpoint**

**Story:** As the frontend, I want a single endpoint to save all journey settings fields so that users can update the journey context without affecting other journey map properties.

**Acceptance Criteria:**
- A PATCH endpoint at `journey_map/settings/{journey_map_id}` accepts any combination of the 12 settings fields
- Only the fields provided in the request body are updated (partial update)
- `updated_at` is refreshed on every successful save
- Returns the updated `journey_map` record
- Rejects unknown fields gracefully

**Layer:** Backend — new file `apis/journey_map/journey_map_settings_journey_map_id_PATCH.xs`

---

**US-JS-04 — Build the Journey Settings panel in the frontend**

**Story:** As a user, I want a dedicated Journey Settings section in the app so that I can view and edit all 12 context fields for the current journey map in one place.

**Acceptance Criteria:**
- A "Journey Settings" panel is accessible from the main Journey Matrix view (e.g. via a settings icon or header button)
- All 12 fields are displayed with their labels and placeholder examples
- Fields render as text inputs or textareas depending on expected length:
  - Short fields (Name, Actor, Start, End, Duration, Version): single-line input
  - Long fields (Scope, Metrics, Stakeholders, Dependencies, Pain Points, Opportunities): textarea
- Empty fields show a placeholder describing what to enter
- The panel is read-only when no journey map is loaded

**Layer:** Frontend — `webapp/protype-2/src/App.tsx` + new component

---

**US-JS-05 — Load and display journey settings from the backend on startup**

**Story:** As a user reopening a journey map, I want the Journey Settings panel to be pre-populated with previously saved values so that context is never lost between sessions.

**Acceptance Criteria:**
- When the journey map bundle loads, all settings fields are read from `journeyMap` record
- The Journey Settings panel is populated before the user opens it
- Fields with `null` values render as empty (not as "null")
- Settings state is reset when a new or different journey map is loaded

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-JS-06 — Save journey settings changes to the backend**

**Story:** As a user, I want my edits to journey settings to be saved automatically or on demand so that context is persisted and available on next load.

**Acceptance Criteria:**
- Changes are saved via the `journey_map/settings/{journey_map_id}` PATCH endpoint
- Save is triggered on blur of each field (auto-save) or via an explicit Save button
- A sync indicator shows while saving; errors surface as inline banners
- Saving does not reload or reset the matrix state
- If no journey map is loaded, save is disabled with a clear message

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/xano.ts`

---

**US-JS-07 — Include journey settings as AI agent context**

**Story:** As the AI agent, I want the journey settings fields included in my context prompt so that every response and matrix update is grounded in the full picture of the journey — not just the cell content.

**Acceptance Criteria:**
- When sending an AI message, the journey settings fields are included in the request payload alongside the selected cell and conversation history
- The AI prompt includes: Journey Name, Primary Actor, Scope, Start/End Points, Duration, and Success Metrics at minimum
- Fields with null values are omitted from the prompt to avoid noise
- Including settings does not break existing AI message flow if fields are empty

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
Frontend — `webapp/protype-2/src/xano.ts` → `sendAiMessage`

