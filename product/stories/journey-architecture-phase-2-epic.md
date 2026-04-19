## Epic: Journey Architecture — Phase 2 (Map Interconnection Layer)

### Context

Phase 2 adds directed connections between Journey Maps within the same architecture.
A **Journey Link** is an edge from a specific cell in a source map to a target map,
with a typed relationship (`exception`, `anti_journey`, `sub_journey`). This enables
modelling the full journey system — e.g. the "Happy Path" map has a cell that breaks
into an "Anti-Journey — Driver Can't Find Address" map.

### Vocabulary

| Term | Meaning |
|---|---|
| **Source map** | The map where the breakpoint originates |
| **Source cell** | The specific cell (stage × lens intersection) in the source map where the link starts |
| **Target map** | The map you break into |
| **Link type** | `exception` / `anti_journey` / `sub_journey` |

### Decisions locked in

| # | Decision |
|---|---|
| Anchor granularity | **Cell-level** — links always start from a specific cell, not a whole stage column |
| Graph library | **ReactFlow (`@xyflow/react`)** — handles draggable nodes, directed edges, zoom/pan |
| Back-navigation | **Standard browser history** — navigating Map A → Map B via a link means browser back returns to Map A naturally. No custom navigation logic needed |
| Duplicate links | **Blocked** — uniqueness is enforced on `(source_cell, target_map)`. One cell can only connect to a given target map once. To change the relationship type, the user edits the existing link rather than creating a second one |

### Explicit non-goals for Phase 2

- Cross-architecture links (links only exist within one architecture)
- Stage-level anchors (cell-level only)
- Nested architectures
- Graph layout auto-generation (node positions are user-controlled)
- Export / reporting of the link graph

---

## Backend Stories

---

### US-JA2-01 — Data model: `journey_link` table

**Story:** As a backend engineer, I want a `journey_link` table to store directed
cell-to-map connections so that the link graph can be queried and rendered.

**Table: `journey_link`**
| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key |
| `created_at` | timestamp | Auto-set to now |
| `updated_at` | date | Updated on every write |
| `journey_architecture` | int → `journey_architecture` | Parent architecture (required) |
| `source_map` | int → `journey_map` | Map where the breakpoint lives |
| `source_cell` | int → `journey_cell` | **Required** — specific cell anchor |
| `target_map` | int → `journey_map` | Map being linked to |
| `link_type` | enum | `exception` / `anti_journey` / `sub_journey` |
| `label` | text | Optional short label shown on the graph edge |
| `owner_user` | int → `user` | Inherited from the architecture |

**Uniqueness constraint:** `(source_cell, target_map)` must be unique.
A cell can point to a given target map only once. Editing the link type updates
the existing record rather than creating a new one.

**Indexes:**
- Primary on `id`
- btree on `(journey_architecture, source_map)`
- btree on `(journey_architecture, target_map)`
- Unique btree on `(source_cell, target_map)`

**Acceptance Criteria:**
- Table created and pushes to Xano without errors
- Unique constraint on `(source_cell, target_map)` — duplicate insert returns a
  validation error
- `source_cell` is required; the API rejects requests without it

---

### US-JA2-02 — `POST /journey_architecture/{id}/link` — Create a link

**Story:** As an authenticated user, I want to create a link from a specific cell
in one map to another map so that I can model breakpoints in the journey system.

**Input:**
- `source_map_id` (int, required)
- `source_cell_id` (int, required) — must belong to `source_map_id`
- `target_map_id` (int, required)
- `link_type` (enum `exception` / `anti_journey` / `sub_journey`, required)
- `label` (text, optional)

**Stack:**
- Fetch the architecture; precondition exists + `owner_user == $auth.id`
- Precondition: both maps belong to this architecture
- Precondition: `source_cell` belongs to `source_map`
- Precondition: `source_map_id != target_map_id` (no self-links)
- Precondition: no existing link with same `(source_cell_id, target_map_id)` —
  return a clear validation error if duplicate detected
- Set `owner_user` from architecture record
- `db.add journey_link`

**Response:** created `journey_link` record

**Acceptance Criteria:**
- Returns 422 if `source_cell_id` is missing
- Returns 422 for self-links (`source_map_id == target_map_id`)
- Returns 422 with message `"A link from this cell to that map already exists"`
  when the `(source_cell, target_map)` pair is not unique
- Returns access denied if source or target map belong to a different architecture
- `owner_user` is always inherited from the architecture, never from client input

---

### US-JA2-03 — `GET /journey_link/{id}` — Get a single link

**Story:** As an authenticated user, I want to fetch a single journey link by ID.

**Stack:**
- Fetch by `id`; precondition exists + `owner_user == $auth.id`

**Response:** single `journey_link` record

---

### US-JA2-04 — `PATCH /journey_link/{id}` — Update a link

**Story:** As an authenticated user, I want to change the `link_type` or `label`
of an existing link without deleting and recreating it.

**Input (all optional):**
- `link_type` (enum)
- `label` (text, filters=trim)

**Stack:**
- Fetch by `id`; precondition exists + owner matches
- Patch only provided fields; set `updated_at = "now"`

**Response:** updated `journey_link` record

**Acceptance Criteria:**
- Omitted fields are unchanged
- `updated_at` refreshed on every successful call
- `source_cell` and `target_map` are **not** patchable — changing those would
  create a different logical link; delete and recreate instead


### US-JA2-05 — `DELETE /journey_link/{id}` — Delete a link

**Story:** As an authenticated user, I want to delete a link between two maps.

**Stack:**
- Fetch by `id`; precondition exists + `owner_user == $auth.id`
- `db.del journey_link`

**Response:** `{ deleted: true, id: <id> }`

---

### US-JA2-06 — Update `GET /journey_architecture/{id}/bundle` — include link graph

**Story:** As the frontend, I want the architecture bundle to include all journey
links so that the UI can render the graph in a single request.

**Changes to bundle endpoint (US-JA-07):**
- Query `journey_link` where `journey_architecture == $id`
- Include as `journey_links` array in the response

**Response:**
```json
{
  "journey_architecture": { ... },
  "journey_maps": [ ... ],
  "journey_links": [
    {
      "id": 1,
      "source_map": 10,
      "source_cell": 42,
      "target_map": 11,
      "link_type": "anti_journey",
      "label": "Driver lost"
    }
  ]
}
```

**Acceptance Criteria:**
- `journey_links` is an empty array (not null) when no links exist
- Each link includes `source_map`, `source_cell`, `target_map`, `link_type`, `label`

---

### US-JA2-07 — Update cascade delete — include `journey_link` cleanup

**Story:** As a backend engineer, I want deleting an architecture or a map to also
delete all related `journey_link` rows so there are no orphaned records.

**Changes to `DELETE /journey_architecture/{id}` (US-JA-06):**
- Before deleting maps, delete all `journey_link` records where
  `journey_architecture == $id`

**Changes to `DELETE /journey_map/{id}` (existing endpoint):**
- Delete all `journey_link` records where `source_map == $id`
  OR `target_map == $id`

**Acceptance Criteria:**
- No orphaned `journey_link` rows after architecture delete
- No orphaned rows after a single map delete
- Deleting an architecture with zero links succeeds cleanly

---

## Frontend Stories

---

### US-JA2-08 — Link badge on map tiles in Architecture Detail

**Story:** As a user in the Architecture Detail view, I want each map tile to show
a badge indicating how many outgoing links it has so I can see at a glance which
maps are connected.

**UX Notes:**
- Small pill badge on the tile: arrow icon + count (e.g. "→ 2")
- Clicking the badge opens a popover listing links:
  `[type icon] → [target map title]` with a "Remove" action per link
- Badge hidden when the map has zero outgoing links

**Acceptance Criteria:**
- Link count derived from `journey_links` in the bundle response — no extra request
- Removing a link calls `DELETE /journey_link/{id}` and removes it from local state
- Popover closes after last link is removed; badge disappears

---

### US-JA2-09 — Create a link from a map tile

**Story:** As a user in the Architecture Detail view, I want to connect two maps
via a link drawer so I can wire up the journey graph without entering the map editor.

**UX Notes:**
- Map tile kebab menu gains **"Add Link →"** option
- Opens a slide-over drawer:
  - **"Link from"**: current map title (read-only)
  - **"Stage"**: dropdown of stages in the source map
  - **"Cell"**: dropdown of cells filtered to the selected stage
  - **"Link type"**: segmented control — Exception / Anti-Journey / Sub-Journey
  - **"Links to"**: dropdown of other maps in this architecture (excludes self)
  - **"Label"**: optional text input
  - **"Add Link"** confirm button

**Acceptance Criteria:**
- `POST /journey_architecture/{id}/link` called on confirm with `source_cell_id`
- New link badge appears on the source tile immediately on success
- If the `(source_cell, target_map)` pair already exists, show inline error:
  *"This cell already links to that map. Edit the existing link instead."*
- "Links to" dropdown never shows the source map itself
- Drawer closes on success; error toast shown on API failure

---

### US-JA2-10 — Architecture graph view (canvas)

**Story:** As a user, I want a visual canvas showing all maps as nodes and all
links as directed edges so I can understand the full journey system at a glance.

**Implementation: ReactFlow (`@xyflow/react`)**

**UX Notes:**
- Toggle between **Grid view** (existing tile grid) and **Graph view** in the
  Architecture Detail header
- Graph nodes: map title, status badge, stage × lens dimensions
- Graph edges: directional arrow labelled with `link_type` and optional `label`
- Nodes are draggable; positions saved to `localStorage` keyed by architecture id
- Clicking a node navigates to the map editor
- Clicking an edge opens a popover to edit `link_type` / `label` or delete the link
- Empty graph (zero links) shows nodes arranged in a row with a "No links yet" hint

**Acceptance Criteria:**
- Graph renders from `journey_links` in the bundle response — no extra API calls
- Node positions persist across page refreshes via `localStorage`
- Toggle state (grid vs graph) persists within the session
- Removing a link via edge popover calls `DELETE /journey_link/{id}` and removes
  the edge immediately

---

### US-JA2-11 — Breakpoint indicator in the Map Editor

**Story:** As a user editing a journey map, I want cells that are the source of a
link to show a small breakpoint indicator so I know this cell connects to another map.

**UX Notes:**
- Small icon overlay on the cell (bottom-right corner): type icon
  (⚠ exception / ↩ anti-journey / ⤵ sub-journey)
- Hovering shows tooltip: **"Links to: [target map title]"** +
  **"View map →"** action
- **"View map →"** navigates to the target map editor

**Back-navigation (standard browser history):**
- Navigation uses `navigate()` — the browser history stack handles back naturally
- Pressing back from the target map returns to the source map (Map A)
- No custom breadcrumb logic needed; the existing Architecture Detail breadcrumb
  already handles returning from any map to `/architectures/{id}`

**Data loading:**
- Extend `loadJourneyMapBundle` to also fetch `journey_link` records where
  `source_map == mapId` — one extra request on map load
- No indicator shown on cells that are not a link source

**Acceptance Criteria:**
- Indicators rendered for all cells that are `source_cell` of a link
- Browser back from target map returns to source map
- "View map →" opens target map in the same tab

---

## Implementation Sequence

```
Backend first:
US-JA2-01 (journey_link table) →
US-JA2-02 (POST create link) →
US-JA2-03 (GET single link) →
US-JA2-04 (PATCH update link) →
US-JA2-05 (DELETE link) →
US-JA2-06 (extend bundle with links) →
US-JA2-07 (cascade delete update)

Frontend after backend is stable:
US-JA2-08 (link badge on tiles) →
US-JA2-09 (create link drawer) →
US-JA2-10 (ReactFlow graph canvas) →
US-JA2-11 (breakpoint indicator in map editor)
```

---

## Dependencies

- Phase 1 fully live (journey_architecture table, all CRUD endpoints, frontend dashboard)
- `journey_cell` records must exist before a link can be created (maps need at least
  one stage + lens to have cells)
- `@xyflow/react` package required for US-JA2-10
- `loadJourneyMapBundle` in `xano.ts` extended for US-JA2-11

---
