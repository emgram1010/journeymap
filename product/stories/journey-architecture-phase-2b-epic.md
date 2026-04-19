# Epic: Journey Architecture — Phase 2b (Cell-Level Link Creation)

## Context

Phase 2 built link creation from the Architecture Detail tile kebab. This required
the user to manually select stage → cell — information they already have when they
are *inside* the map editor looking at a specific cell. Phase 2b moves link creation
into the Cell Detail panel where the source anchor is already known, and adds the
ability to spin up a new child map in the same action.

## Decision log

| Decision | Choice | Reason |
|---|---|---|
| Where to create links | Cell Detail panel in the map editor | Source cell is already selected — no redundant dropdowns |
| When no arch context | Hidden entirely | Linking only makes sense inside an architecture; disabled state adds noise |
| Tile-level "Add Link →" | Removed from kebab | Superseded by cell-level UX; link badge (read-only) stays on tiles |
| Create new map in link flow | Yes — inline title input | Lets users model anti-journeys/sub-journeys without leaving context |
| Post-create navigation | Navigate to new map with `?arch=` | Keeps architecture context for back button |

## Non-goals for Phase 2b

- Bulk-linking multiple cells at once
- Editing an existing link from the cell panel (delete existing via tile badge; re-create)
- Showing the full link graph from inside the map editor

---

## Stories

---

### US-JA2-15 — "Link to Map" section in Cell Detail panel

**Story:** As a user editing a cell in a map that belongs to an architecture, I want
a "Link to Map" section at the bottom of the Cell Detail panel so I can create a
journey link directly from the cell I am focused on — without having to navigate
back to the architecture view and locate the correct cell manually.

**Trigger:** Only rendered when `?arch={id}` is present in the URL (i.e. the map
was opened from an Architecture Detail). Hidden entirely for standalone maps.

**Layout (bottom of Cell Detail panel, above "Save & Close"):**

```
─────────────────────────────────────
Link to Map              (section label)

Link type   [Exception] [Anti-Journey] [Sub-Journey]

Links to    [Select a map or create new…  ▾]
             ↳ if "Create new map" selected:
               [Map title input          ]

            [Add Link →]  (disabled until all fields filled)
            ← success: "↩ Linked" badge replaces button
            ← error: inline red message
─────────────────────────────────────
```

**Sibling map loading:**
- Loaded lazily on first render of the section (one call to the architecture bundle)
- Filtered to exclude the current map

**Acceptance Criteria:**
- Section is hidden when `architectureId` is null
- Sibling maps loaded from `GET /journey_architecture/{id}/bundle`
- "Links to" dropdown lists all sibling maps + a `+ Create new map` option at the bottom
- Selecting an existing map and clicking "Add Link →" calls `POST /journey_architecture/{id}/link`
- On success: cell breakpoint indicator (⚠/↩/⤵) appears on the cell immediately
- On duplicate: inline error "This cell already links to that map"
- On any other error: inline error "Failed to create link. Please try again."
- Form resets when a different cell is selected

---

### US-JA2-16 — Create new child map from link flow

**Story:** As a user, when creating a link from a cell I want the option to create
a brand-new journey map as the target so that I can model anti-journeys and
sub-journeys without leaving my current editing context.

**UX flow:**
1. User selects "+ Create new map" in the "Links to" dropdown
2. A title input appears: placeholder "e.g. Anti-Journey — Driver Can't Find Address"
3. User fills in the title (optional — defaults to "Untitled Journey Map")
4. Clicks "Add Link →"
5. App: `createDraftJourneyMap({ title, journey_architecture_id })` → get new map id
6. App: `createJourneyLink({ source_cell_id, target_map_id: newMap.id, link_type })`
7. Navigate to `/maps/{newMapId}?arch={archId}` — opens the new map editor
8. Back button in new map → returns to source map (correct `?arch=` param preserved)

**Acceptance Criteria:**
- Title input shown only when "+ Create new map" is selected
- Both API calls (`createDraftJourneyMap` + `createJourneyLink`) made before navigation
- If `createDraftJourneyMap` succeeds but `createJourneyLink` fails: navigate to the
  new map anyway and show a toast "Map created but link failed — add it manually"
- New map appears in the sibling maps list on the Architecture Detail when navigating back
- Cell indicator appears on source cell immediately after link creation

---

### US-JA2-17 — Remove tile-level "Add Link →" from Architecture Detail

**Story:** As a maintainer, I want to remove the "Add Link →" option from the map
tile kebab menu and the associated `LinkDrawer` component now that cell-level link
creation is the canonical flow.

**What is removed:**
- `onAddLink` prop from `MapTileProps` and `MapTile` component
- "Add Link →" button from the tile kebab menu
- `LinkDrawer` component (entire component)
- `linkDrawerMap` state in `ArchitectureDetail`
- `listJourneyStagesForMap` and `listJourneyCellsForMap` imports (no longer used here)

**What stays:**
- Link count badge on tiles (read-only — still useful at-a-glance)
- Link popover with "Remove" action per link
- `handleRemoveLink` handler

**Acceptance Criteria:**
- Tile kebab menu shows: Rename / Archive / Delete (no "Add Link →")
- No regressions on link badge display or link removal from popover

---

## Implementation sequence

```
US-JA2-17 (remove tile LinkDrawer — cleanup first) →
US-JA2-15 (cell-level section in App.tsx) →
US-JA2-16 (create new map option — part of same App.tsx edit)
```

No backend changes required — all existing endpoints are sufficient.
