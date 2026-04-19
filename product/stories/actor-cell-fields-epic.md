## Actor Cell Fields Epic

### Purpose

Surface the structured actor-specific fields inside the Cell Detail Panel so that each cell at the intersection of an actor row × stage shows and captures the right information for that actor's role — not just a generic content textarea. Starting with the Customer actor template (`customer-v1`).

### Context

The previous epic (`actor-lens-template-epic.md`) built:
- The actor identity on the lens row (who the actor IS across the whole journey)
- The `actor_fields` JSON scaffold on each cell at creation time (9 keys, all null)
- The `actor_fields` mapped through to the frontend `MatrixCell` type

This epic builds the **editing and display** layer — the cell panel UI, the save path, and the AI integration for the structured fields.

### What the Customer Cell Fields Look Like

When a Customer actor row is selected and a stage cell is opened, the Cell Detail Panel shows 9 structured fields instead of (or alongside) the generic content textarea:

| # | Key | Label | Placeholder |
|---|---|---|---|
| 1 | `entry_trigger` | Entry Point / Trigger | e.g. Saw an ad online, walked into a store |
| 2 | `emotions` | Feelings / Emotions | e.g. Anxious about making the right choice |
| 3 | `information_needs` | Information Needs | e.g. Is installation included? What are the dimensions? |
| 4 | `decisions_required` | Decisions Required | e.g. Delivery date, haul away old unit, payment method |
| 5 | `friction_points` | Friction Points | e.g. Unclear fees, no real-time availability shown |
| 6 | `assumptions` | Assumptions | e.g. Assumes installation is included in the price |
| 7 | `acceptance_criteria` | Acceptance Criteria | e.g. Order confirmed, delivery date visible, cost clear |
| 8 | `expected_output` | Expected Output | e.g. Confirmation email with order number and next steps |
| 9 | `channel_touchpoint` | Channel / Touchpoint | e.g. Website, mobile app, in-store, call center |

The generic `Content` textarea is **retained as a Notes field** below the structured fields — legacy rows and AI freetext still have a place to live.

### Scope

- Backend: update cell PATCH endpoint to accept `actor_fields`
- Frontend types: no new types needed (already typed as `ActorFields`)
- Frontend `xano.ts`: extend `updateJourneyCell` to pass `actor_fields`
- Frontend `App.tsx`: render structured cell fields in the Cell Detail Panel when the parent lens has an `actor_type`; wire field edits to local state + save on "Save & Close"
- AI agent: pass the 9 structured field values as additional context when filling a customer cell

### Explicit Non-Goals

- Cell field UI for Operations, AI Agent, Dev actor types (future epic)
- Per-field AI fill (fill one field at a time) — AI fills the whole cell for now
- Field-level lock or confirmation status

---

### Epic: Actor Cell Fields — Customer

---

**US-ACF-01 — Update cell PATCH endpoint to accept actor_fields**

**Story:** As the frontend, I want to save structured `actor_fields` back to a cell so that the 9 customer fields persist to the database when the user edits them.

**Acceptance Criteria:**
- `44_journey_cell_update_journey_cell_id_PATCH.xs` accepts a new optional `json actor_fields?` input field
- When `actor_fields` is present in the request body it is included in the `db.patch` data
- The API response includes `actor_fields` so the frontend can confirm what was saved
- Existing calls that omit `actor_fields` are fully backward-compatible
- The stale-target guard (stage and lens existence check) is unchanged

**Layer:** Backend — `apis/journey_map/44_journey_cell_update_journey_cell_id_PATCH.xs`

---

**US-ACF-02 — Extend updateJourneyCell to pass actor_fields**

**Story:** As the frontend API layer, I want `updateJourneyCell` to optionally pass `actor_fields` so that structured field edits are persisted alongside content, status, and lock state.

**Acceptance Criteria:**
- `UpdateJourneyCellInput` type gains an optional `actorFields?: ActorFields | null` property
- `updateJourneyCell` includes `actor_fields` in the PATCH body when the field is present in the input
- `actor_fields` is omitted from the body when not provided (no null-write on untouched cells)
- The returned `XanoJourneyCell` already includes `actor_fields` — no interface change needed

**Layer:** Frontend — `webapp/protype-2/src/xano.ts`

---

**US-ACF-03 — Render structured customer fields in the Cell Detail Panel**

**Story:** As a user, when I select a cell in a Customer actor row, I want to see the 9 structured customer fields in the Cell Detail Panel so that I can fill in the right information for that stage.

**Acceptance Criteria:**
- When `selectedCell.actorFields` is non-null AND the parent lens `actorType === 'customer'`, the Cell Detail Panel shows the 9 customer fields as individual labeled textareas
- Each field has the correct label and placeholder (see table above)
- Fields render in the order defined in the template
- Empty fields show the placeholder; filled fields show the saved value
- The generic `Content` textarea is relabeled "Notes" and remains below the structured fields
- When the parent lens has no `actorType` (legacy row), only the "Notes" textarea is shown — no regression
- When the cell is locked, all structured fields are read-only (same as the existing Content lock behavior)
- The layout is scrollable — all 9 fields + Notes fit within the fixed-height panel

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`

---

**US-ACF-04 — Wire structured field edits to local state and Save & Close**

**Story:** As a user, I want edits to the structured customer cell fields to be saved when I click "Save & Close" so that my changes persist to the database.

**Acceptance Criteria:**
- Editing any of the 9 structured fields updates the cell's `actorFields` in local state (mirrors how `content` edits work today)
- The existing `persistCellChanges` / `cellPendingChanges` mechanism is extended to include `actorFields` changes
- "Save & Close" calls `updateJourneyCell` with both `content` (Notes) and `actor_fields` when either has changed
- If neither content nor actorFields has changed, no PATCH is issued (same as current behavior)
- After a successful save, the matrix cell preview in the grid updates to reflect the new data
- Unsaved actor field changes trigger the same "unsaved changes" guard that content changes trigger today

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`, `webapp/protype-2/src/cellPersistence.ts`

---

**US-ACF-05 — Show structured field summary in the matrix cell preview**

**Story:** As a user, I want the matrix cell tile to show a summary of the actor fields that have been filled so that I can see at a glance how complete a cell is without opening the detail panel.

**Acceptance Criteria:**
- For customer actor cells, the cell tile shows a count of filled fields out of 9 (e.g. "3 / 9 fields")
- If `actor_fields` is null or all values are null, the tile shows "No data" as before
- If at least one field is filled, the tile shows the count badge alongside or instead of the content preview
- Non-actor cells are unaffected — they continue to show the `content` text preview
- The count display is compact and does not break the existing cell tile layout

**Layer:** Frontend — `webapp/protype-2/src/JourneyMatrixTabulator.tsx` (cell formatter)

---

**US-ACF-06 — Inject structured customer cell fields into AI agent context**

**Story:** As the AI agent, I want to see which of the 9 customer cell fields are already filled and which are empty so that I can target my response to complete the gaps rather than repeat what is already there.

**Acceptance Criteria:**
- When the AI message API processes a selected cell whose parent lens is a customer actor, it reads `actor_fields` from the cell record
- Filled fields are included in the dynamic context as "already captured" data
- Empty (null) fields are listed as "fields to complete" — the agent focuses its response on those
- The agent response format matches the structured field keys so the output can be parsed and mapped back to individual fields
- If all 9 fields are filled, the agent is informed the cell is complete and offers refinement instead of fill
- If `actor_fields` is null (legacy or non-actor cell), the existing content-based context is used unchanged

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
