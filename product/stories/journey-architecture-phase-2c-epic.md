# Journey Architecture — Phase 2c: Anti-Journey Parent Context

**Epic goal:** When a user is inside an anti-journey (or exception / sub-journey) map that was spawned from a parent map cell, the editor surfaces the originating context — what stage and lens the breakpoint came from and what the source cell said — as a read-only orientation strip and injects that same context into every AI agent call.

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Source of truth for inbound links | `GET /journey_link?target_map={id}` (existing `74_journey_link_GET.xs`) | No new endpoint; works with architecture context already in URL |
| 2 | Source of truth for trigger cell content | `GET /journey_cell/{id}` (existing `36_journey_cell_journey_cell_id_GET.xs`) | Cell record holds `content`, `actor_fields`, `stage`, `lens` |
| 3 | Multiple inbound links | Show most-recently-created link | 1:1 is the 99 % case from "create new map" flow; avoids UI complexity |
| 4 | Parent map title | Loaded from architecture bundle `siblingMaps` already in memory | Zero extra API calls |
| 5 | AI injection mechanism | Add `parent_context` field to `sendAiMessage` body | Backend endpoint already accepts arbitrary context keys |
| 6 | Strip placement | Fixed row below the editor top bar, above the matrix | Always visible without scrolling |
| 7 | "View source" navigation | Navigate to `/maps/{source_map}?arch={archId}&highlight={source_cell}` | Reuses existing architecture-aware routing |

---

## Vocabulary

| Term | Definition |
|---|---|
| **Inbound link** | A `journey_link` record where `target_map` equals the currently-open map |
| **Source cell** | The `journey_cell` referenced by `inbound_link.source_cell` — the exact breakpoint |
| **Trigger content** | `source_cell.content` — the text in the cell that caused the handoff |
| **Parent context** | The combined data (link type, parent map title, stage/lens labels, trigger content) shown in the strip and sent to the AI |
| **Orientation strip** | A fixed UI row below the top nav that displays parent context |

---

## User Stories

### US-JA2C-01 — Load inbound parent context on map open

**As a** journey architect  
**When I** open any map that has an inbound `journey_link` record pointing to it (i.e. it is a child map)  
**I want** the editor to silently fetch the inbound link and its source cell in the background  
**So that** parent context is available for display and AI injection without a manual action.

**Acceptance criteria:**
- On map load, if `architectureId` is present in the URL, call `GET /journey_link?target_map={mapId}`
- If one or more links are returned, take the most recent (`created_at` descending)
- Call `GET /journey_cell/{source_cell}` to hydrate the trigger cell record
- Resolve the parent map title from the already-loaded `siblingMaps` in architecture state
- Store the result as `inboundContext` state; keep `null` if no inbound links exist
- Errors are silent (do not block the editor from loading)

---

### US-JA2C-02 — Orientation strip (UI)

**As a** journey architect  
**When I** am inside a child map (anti-journey, exception, sub-journey)  
**I want** to see a compact strip below the top bar showing where this map came from  
**So that** I always know the failure context I am modelling without navigating away.

**Acceptance criteria:**
- Strip is only shown when `inboundContext` is non-null
- Strip shows: link type icon + label (e.g. `↩ Anti-Journey`), parent map title, stage × lens reference, and trigger cell content (truncated to ~120 chars with ellipsis)
- Strip has a `View source →` button
- Clicking `View source →` navigates to `/maps/{source_map}?arch={archId}` (same tab)
- Strip uses a visually distinct but non-intrusive style (e.g. amber/indigo accent, 1-line height)
- If trigger content is empty, show `"No content recorded at this cell"` in muted style

---

### US-JA2C-03 — AI parent context injection

**As a** journey architect  
**When I** send a message to the AI agent while inside a child map  
**I want** the AI to know the parent trigger context automatically  
**So that** AI suggestions are relevant to the specific failure scenario being modelled.

**Acceptance criteria:**
- When `inboundContext` is set, include a `parent_context` field in the AI message payload:
  ```json
  {
    "link_type": "anti_journey",
    "parent_map_title": "Delivery Flow",
    "source_stage_label": "Last-Mile Delivery",
    "source_lens_label": "Customer",
    "trigger_content": "Driver couldn't find the pickup location"
  }
  ```
- `parent_context` is omitted from the payload when `inboundContext` is null
- The AI backend endpoint must accept the new field without breaking existing calls

---

### US-JA2C-04 — Stage and lens label resolution for source cell

**As a** system  
**When I** load the source cell record (which only stores integer IDs for `stage` and `lens`)  
**I want** the stage and lens labels to be resolved from the parent map's stage/lens list  
**So that** the orientation strip shows human-readable "Stage 2 × Customer" rather than raw IDs.

**Acceptance criteria:**
- After fetching the source cell, call `GET /journey_map/load_bundle/{source_map}` (existing endpoint) to get stages and lenses for the parent map
- Resolve `source_cell.stage` → `stage.label` and `source_cell.lens` → `lens.label`
- Store resolved labels in `inboundContext`
- Fallback to `"Stage {id}"` / `"Lens {id}"` if resolution fails

---

## Out of Scope (Phase 2c)

- Showing the full parent map matrix inline inside the child editor
- Multi-level ancestry chains (grandparent context)
- Editable parent context
- Notifications or sync when the source cell changes in the parent
