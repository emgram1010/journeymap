## Epic 8: Journey Map Dashboard — Browse & CRUD

### Context

After authentication, users need a home base: a visual dashboard that shows all their
journey maps as browsable tiles, lets them create new ones, and gives them quick actions
to rename, archive, or delete a map without opening it.

The backend already provides:
- `GET /journey_map` — list all maps
- `POST /journey_map/create_draft` — create a new draft with default scaffold
- `PUT /journey_map/{id}` — full update
- `PATCH /journey_map/{id}` — partial update (rename, status change)
- `DELETE /journey_map/{id}` — delete

This epic wires those endpoints into a dashboard experience that precedes the existing
journey map editor, giving the product a coherent start-to-finish user journey.

### Explicit non-goals for this phase

- Sharing or collaborating on maps with other users
- Filtering or sorting controls beyond recency
- Bulk select and bulk delete
- Folder/tag organisation

---

### US-DASH-01 — Dashboard layout: tile grid of journey maps

**Story:** As a signed-in user, I want to land on a dashboard that shows all my journey
maps as visual tiles so that I can orient quickly and pick up where I left off.

**UX Notes:**
- Page header: brand mark left, user avatar chip right (links to sign-out dropdown).
- Page title: **"Your Journey Maps"** with a subtle count badge (e.g. "4 maps").
- Primary action button: **"+ New Journey Map"** — top-right, prominent.
- Tile grid: responsive, 3 columns on desktop, 2 on tablet, 1 on mobile.
- Each tile shows: map **title**, **status badge** (Draft / Active / Archived),
  **relative last-updated timestamp** (e.g. "Updated 2 hours ago"), and a
  **kebab menu** (⋯) for rename, archive, delete.
- Tiles are sorted by `last_interaction_at` descending (most recently touched first).
- Clicking the tile body (not the menu) opens the map in the editor.

**Acceptance Criteria:**
- `GET /journey_map` is called on mount with the auth token.
- Maps are rendered as tiles sorted by most-recently updated.
- A loading skeleton is shown while the request is in flight.
- A network error shows a non-blocking error banner with a "Retry" action.
- The tile count badge updates whenever the list changes.

---

### US-DASH-02 — Empty state and create-first-map CTA

**Story:** As a new user who has no maps yet, I want to see a clear prompt to create my
first journey map so that I am never left staring at a blank screen.

**UX Notes:**
- Full-height empty state illustration area (simple line art or icon, not a photo).
- Headline: **"No journey maps yet"**
- Subline: **"Create your first map to start capturing expert knowledge."**
- Single large CTA button: **"Create your first journey map"** (same action as the
  header "+ New Journey Map" button above).
- Empty state disappears the moment the first map is created.

**Acceptance Criteria:**
- Empty state is shown only when `GET /journey_map` returns an empty array.
- Clicking either CTA triggers the same create-map flow (US-DASH-04).
- If a map is deleted and no maps remain, the empty state re-appears immediately.

---

### US-DASH-03 — Journey map tile design and status badge

**Story:** As a user scanning my dashboard, I want each tile to clearly communicate the
map's state and recency so that I can prioritise my work at a glance.

**UX Notes:**
- Tile: white card, 1px zinc-200 border, rounded-lg, subtle shadow on hover.
- Status badge styles:
  - **Draft** → zinc background, zinc text (neutral / in-progress)
  - **Active** → green background, green text (live / in-use)
  - **Archived** → amber background, amber text (dormant)
- Timestamp formatted as relative time (< 1 min, X min ago, X hr ago, then date).
- Kebab menu (⋯) appears on tile hover; always visible on touch devices.
- Tile footer shows a small row of cell-status indicators if data is available
  (confirmed count, draft count, open count — matching the editor's colour language).

**Acceptance Criteria:**
- Status badge renders the correct colour for all three statuses.
- Timestamp updates format correctly from seconds through days.
- Kebab menu does not propagate a click through to the tile open action.
- Tile renders gracefully when the map has no stages/lenses yet (new draft).

---

### US-DASH-04 — Create a new journey map

**Story:** As a user, I want to create a new journey map with a single click so that I
can start capturing knowledge without setup friction.

**UX Notes:**
- Clicking "+ New Journey Map" immediately calls `POST /journey_map/create_draft` with
  a default title ("Untitled Journey Map") — **no modal required**.
- A loading spinner replaces the button label during the request.
- On success, the new map tile appears at the top of the grid AND the app navigates
  directly into the editor for that map (zero extra clicks to start working).
- If the user later renames the map (US-DASH-06), the title updates on the dashboard
  when they navigate back.

**Acceptance Criteria:**
- `POST /journey_map/create_draft` is called with auth token and `user_id` as `owner_user`.
- The response map is inserted at the top of the local tile list before navigation.
- Navigation to the editor happens only after a successful API response.
- A failed create shows an error banner; the button returns to its default state.

---

### US-DASH-05 — Open and navigate into a journey map

**Story:** As a user, I want clicking a map tile to open the full journey map editor so
that I can continue where I left off.

**UX Notes:**
- Clicking the tile (not the kebab) navigates to `/maps/{id}`.
- The editor receives the `journey_map_id` from the URL, not from local state, so the
  page is directly linkable and refreshable.
- The editor's existing "loading from Xano" skeleton is shown while the bundle loads.
- A **"← Back to Dashboard"** breadcrumb/link appears in the editor header so the user
  can return to the dashboard without using the browser back button.

**Acceptance Criteria:**
- URL changes to `/maps/{id}` on tile click.
- Refreshing `/maps/{id}` loads the correct map without requiring dashboard visit first.
- "← Back to Dashboard" navigates to `/dashboard` and restores the tile list.
- The editor still works for users who navigated directly to a map URL.

---

### US-DASH-06 — Rename a journey map from the dashboard

**Story:** As a user, I want to rename a map from the dashboard tile without opening the
full editor so that I can keep my map list organised quickly.

**UX Notes:**
- Selecting **"Rename"** from the tile kebab menu opens an **inline editable title** on
  the tile itself (not a modal) — the title text becomes an input field.
- Pressing **Enter** or clicking outside the field saves (calls `PATCH /journey_map/{id}`
  with the new title).
- Pressing **Escape** cancels without saving.
- Empty or whitespace-only titles revert to the previous value with a shake animation.

**Acceptance Criteria:**
- `PATCH /journey_map/{id}` is called only when the title has actually changed.
- The tile updates optimistically on Enter; reverts on API failure with an error toast.
- Whitespace-only input is trimmed and treated as empty (rejected).
- The rename action is also available inside the editor's header (same API call).

---

### US-DASH-07 — Delete a journey map

**Story:** As a user, I want to delete a journey map I no longer need so that my
dashboard stays relevant and uncluttered.

**UX Notes:**
- Selecting **"Delete"** from the tile kebab opens a **small confirmation popover**
  anchored to the tile (not a full-screen modal).
- Popover copy: **"Delete '{map title}'?"** with subtext **"This will permanently
  remove the map and all its stages, lenses, and cells. This cannot be undone."**
- Two buttons: **"Cancel"** (secondary) and **"Delete"** (red/destructive).
- On confirm: tile fades out with a brief animation, then the empty state appears if
  no maps remain.

**Acceptance Criteria:**
- `DELETE /journey_map/{id}` is called only after explicit confirmation.
- The tile is removed from local state immediately on API success (optimistic removal).
- A failed delete shows a toast error and restores the tile.
- Deleting the currently-open map from another tab (or edge case) is handled gracefully.

---

### US-DASH-08 — Archive a journey map

**Story:** As a user, I want to archive a map I am done with so that it leaves my active
list but is not permanently lost.

**UX Notes:**
- Selecting **"Archive"** from the tile kebab sends `PATCH /journey_map/{id}` with
  `status: "archived"`.
- Archived maps are visually dimmed on the dashboard and sorted to the bottom.
- An **"Unarchive"** option appears in the kebab for already-archived tiles.
- Future phase: a toggle to show/hide archived maps (out of scope now — archived maps
  are shown but de-emphasised in this phase).

**Acceptance Criteria:**
- Archiving changes the status badge to Archived and moves the tile to the end of the list.
- Unarchiving restores status to `draft` and re-sorts the tile by recency.
- Both actions call `PATCH /journey_map/{id}` with the correct status value.

---

### User flow diagram

```
/login ──(success)──► /dashboard
                          │
               ┌──────────┴──────────┐
               │                     │
         [tile click]         [+ New Journey Map]
               │                     │
               ▼                     ▼
         /maps/{id}           POST create_draft
         (editor)              → /maps/{new_id}
               │
        [← Back to Dashboard]
               │
               ▼
         /dashboard
```

---

### Recommended implementation sequence

```
US-DASH-01 (tile grid + load) →
US-DASH-02 (empty state) →
US-DASH-03 (tile design / badges) →
US-DASH-04 (create new map) →
US-DASH-05 (open map / URL routing) →
US-DASH-06 (rename) →
US-DASH-07 (delete with confirmation) →
US-DASH-08 (archive / unarchive)
```

### Dependencies

- Epic 7 (US-AUTH-03) must land first — protected routing and auth token in headers.
- React Router must be added before US-DASH-05 can be implemented.
- The existing editor (`App.tsx`) must be adapted to accept `journey_map_id` from the
  URL param rather than always loading the first available map.
- US-DASH-04 depends on `owner_user` (user_id from auth context) being passed correctly.
