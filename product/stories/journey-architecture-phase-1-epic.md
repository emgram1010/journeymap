## Epic: Journey Architecture — Phase 1 (Container Layer)

### Context

A **Journey Architecture** is a named parent container that groups one or more Journey Maps
together under a single organising unit. Think of it as the folder above the maps — for
example, *"Pizza Delivery Experience"* is the architecture, and *"Happy Path — Order to
Delivery"* and *"Anti-Journey — Driver Can't Find Address"* are the maps inside it.

Phase 1 scope: create, manage, and browse Journey Architectures and create Journey Maps
inside them. Journey-to-journey interconnection (links, breakpoints, anti-journey graph)
is Phase 2 and is explicitly out of scope here.

### Ownership model

When a Journey Map is created inside a Journey Architecture, it **inherits** the
architecture's `owner_user` and `account_id`. Journey Maps created outside an architecture
retain their own ownership as before (nullable `journey_architecture` FK).

### Explicit non-goals for Phase 1

- Journey-to-journey links or breakpoint connections
- Shared / multi-user ownership of an architecture
- Nesting architectures inside architectures
- Export or reporting across an architecture

---

## Backend Stories

---

### US-JA-01 — Data model: `journey_architecture` table + FK on `journey_map`

**Story:** As a backend engineer, I want a `journey_architecture` table and a nullable
foreign key on `journey_map` so that maps can optionally belong to an architecture.

**Table: `journey_architecture`**
| Field | Type | Notes |
|---|---|---|
| `id` | int | Primary key |
| `created_at` | timestamp | Auto-set to now, private |
| `updated_at` | date | Updated on every write |
| `title` | text | filters=trim |
| `description` | text | Optional, filters=trim |
| `status` | enum | `draft` / `active` / `archived` |
| `owner_user` | int → `user` | Owner FK |
| `account_id` | int → `account` | Account FK |

**Migration: `journey_map` table**
- Add nullable field: `journey_architecture` (int → `journey_architecture`)
- Existing maps with `null` are unaffected — standalone maps remain valid

**Indexes on `journey_architecture`:**
- Primary on `id`
- GIN on `xdo` (jsonb_path_op)
- btree on `created_at` desc
- btree on `(owner_user, account_id, updated_at desc)`

**Acceptance Criteria:**
- Table is created and pushes to Xano without errors
- `journey_map.journey_architecture` FK is nullable; existing rows unaffected
- All new and existing workflow tests continue to pass

---

### US-JA-02 — `POST /journey_architecture` — Create a Journey Architecture

**Story:** As an authenticated user, I want to create a new Journey Architecture so that
I have a container to organise my related journey maps.

**Input:**
- `title` (text, optional, defaults to `"Untitled Journey Architecture"`)
- `description` (text, optional)
- `status` (enum, optional, defaults to `"draft"`)
- `account_id` (int → `account`, optional)

**Stack:**
- `owner_user` is derived from `$auth.id` — never accepted from client input
- `status` defaults to `"draft"` if not provided
- `title` defaults to `"Untitled Journey Architecture"` if blank

**Response:** the created `journey_architecture` record

**Acceptance Criteria:**
- Returns the new record with `id`, `created_at`, `owner_user` populated
- `owner_user` is always the authenticated user regardless of input
- Blank title input falls back to the default string

---

### US-JA-03 — `GET /journey_architecture` — List architectures for auth user

**Story:** As an authenticated user, I want to list all my Journey Architectures so that
I can see everything I own and navigate into one.

**Stack:**
- Query `journey_architecture` where `owner_user == $auth.id`
- Sort by `updated_at` desc

**Response:** array of `journey_architecture` records

**Acceptance Criteria:**
- Only records owned by the authenticated user are returned
- Results are sorted most-recently-updated first
- Returns empty array (not error) when user has no architectures

---

### US-JA-04 — `GET /journey_architecture/{id}` — Get a single architecture

**Story:** As an authenticated user, I want to fetch a single Journey Architecture by ID
so that I can read its metadata before loading its maps.

**Stack:**
- Fetch `journey_architecture` by `id`
- Precondition: record exists (`notfound` error if not)
- Precondition: `owner_user == $auth.id` (`accessdenied` error if not)

**Response:** single `journey_architecture` record

**Acceptance Criteria:**
- Returns 404-equivalent error for unknown ID
- Returns access denied error if the record belongs to a different user

---

### US-JA-05 — `PATCH /journey_architecture/{id}` — Update an architecture

**Story:** As an authenticated user, I want to rename or update the description and status
of a Journey Architecture so that I can keep it organised as my work evolves.

**Input (all optional):**
- `title` (text, filters=trim)
- `description` (text, filters=trim)
- `status` (enum: `draft` / `active` / `archived`)

**Stack:**
- Fetch existing record; precondition not null + owner matches auth
- Use raw input key detection to patch only provided fields (same pattern as
  `journey_map/{id}` PATCH)
- Set `updated_at` to `"now"` on every successful write

**Response:** updated `journey_architecture` record

**Acceptance Criteria:**
- Only fields present in the request body are written; omitted fields are unchanged
- `updated_at` is refreshed on every successful call
- Access denied if user does not own the record

---

### US-JA-06 — `DELETE /journey_architecture/{id}` — Delete an architecture

**Story:** As an authenticated user, I want to delete a Journey Architecture so that I can
remove containers I no longer need.

**Stack:**
- Fetch existing record; precondition not null + owner matches auth
- Delete all `journey_map` records where `journey_architecture == $id`
  (cascade: stages, lenses, cells, agent conversations and messages per each map)
- Delete the `journey_architecture` record

**Response:** `{ deleted: true, id: <id> }`

**Acceptance Criteria:**
- All child journey maps and their stages, lenses, cells are deleted
- Returns not-found error for unknown ID
- Returns access denied if user does not own the record
- Deleting an architecture with zero maps succeeds cleanly

---

### US-JA-07 — `GET /journey_architecture/{id}/bundle` — Architecture bundle

**Story:** As an authenticated user, I want to load a Journey Architecture and all its
Journey Maps in a single request so that the frontend can render the architecture detail
view without multiple round trips.

**Stack:**
- Fetch `journey_architecture` by id; precondition exists + owner matches
- Query `journey_map` where `journey_architecture == $id`, sort `updated_at` desc
- Return both as a combined response

**Response:**
```json
{
  "journey_architecture": { ...architecture record },
  "journey_maps": [ ...array of journey_map records ]
}
```

**Acceptance Criteria:**
- Returns the architecture record and its maps in one response
- `journey_maps` is an empty array (not null) when no maps exist yet
- Access denied if user does not own the architecture

---

### US-JA-08 — Update `POST /journey_map/create_draft` — accept `journey_architecture_id`

**Story:** As an authenticated user, I want to create a Journey Map inside a Journey
Architecture so that the new map is automatically grouped and inherits ownership.

**Changes to `journey_map/create_draft`:**
- Accept optional input: `journey_architecture_id` (int → `journey_architecture`)
- If provided:
  - Validate the architecture exists and is owned by `$auth.id`
  - Set `journey_map.journey_architecture = $input.journey_architecture_id`
  - Inherit `owner_user` and `account_id` from the architecture record
- If not provided: existing behaviour is unchanged (standalone map)

**Response:** unchanged — same bundle response as today

**Acceptance Criteria:**
- Map created with `journey_architecture_id` has the correct FK set
- `owner_user` and `account_id` are copied from the architecture, not from raw input
- Passing an unknown or unowned `journey_architecture_id` returns a validation error
- Creating without `journey_architecture_id` still works as before (no regression)

---

### US-JA-09 — Update `GET /journey_map` — filter by architecture

**Story:** As an authenticated user, I want to list only the Journey Maps that belong to a
specific Journey Architecture so that the architecture detail view shows the right maps.

**Changes to `GET /journey_map`:**
- Accept optional input: `journey_architecture_id` (int)
- If provided: add `journey_map.journey_architecture == $input.journey_architecture_id`
  to the existing `owner_user` filter
- If not provided: existing behaviour unchanged (returns all maps for auth user)

**Acceptance Criteria:**
- Passing `journey_architecture_id` returns only maps belonging to that architecture
- Omitting it returns all maps for the user as before
- Returns empty array (not error) when architecture exists but has no maps yet

---

## Frontend Stories

---

### US-JA-10 — Architecture dashboard: tile grid of architectures

**Story:** As a signed-in user, I want to land on an Architecture dashboard that shows all
my Journey Architectures as tiles so that I can orient quickly and navigate into one.

**UX Notes:**
- Page title: **"Your Journey Architectures"** with a count badge (e.g. "3 architectures")
- Primary action: **"+ New Architecture"** button — top-right, prominent
- Tile grid: responsive, 3 columns desktop / 2 tablet / 1 mobile
- Each tile shows: architecture **title**, **status badge** (Draft / Active / Archived),
  **relative last-updated timestamp**, **journey map count** (e.g. "4 maps"), and a
  **kebab menu** (⋯) for rename, archive, delete
- Tiles sorted by `updated_at` descending
- Clicking a tile opens the architecture detail view (US-JA-13)

**Acceptance Criteria:**
- `GET /journey_architecture` called on mount with auth token
- Tiles render with correct title, status badge colour, timestamp, and map count
- Loading skeleton shown while request is in flight
- Network error shows non-blocking banner with "Retry" action

---

### US-JA-11 — Empty state and create-first-architecture CTA

**Story:** As a new user with no architectures, I want a clear prompt to create my first
Journey Architecture so that I am never left staring at a blank screen.

**UX Notes:**
- Full-height empty state with icon/illustration
- Headline: **"No Journey Architectures yet"**
- Subline: **"Create an architecture to start organising your journey maps."**
- Single large CTA: **"Create your first architecture"**

**Acceptance Criteria:**
- Empty state shown only when `GET /journey_architecture` returns an empty array
- Clicking CTA triggers the same create flow as US-JA-12
- Empty state disappears the moment the first architecture is created

---

### US-JA-12 — Create a new Journey Architecture

**Story:** As a user, I want to create a new Journey Architecture with a single click so
that I can immediately start adding journey maps to it.

**UX Notes:**
- Clicking "+ New Architecture" calls `POST /journey_architecture` with default title
  — **no modal required**
- Spinner replaces button label during the request
- On success: new tile appears at the top of the grid AND the app navigates directly
  into the architecture detail view for that architecture

**Acceptance Criteria:**
- `POST /journey_architecture` called with auth token; `owner_user` set server-side
- New architecture tile inserted at the top of local list before navigation
- Navigation to detail view happens only after a successful API response
- Failed create shows error banner; button returns to default state

---

### US-JA-13 — Open an architecture: detail view with its journey maps

**Story:** As a user, I want to open a Journey Architecture and see all the Journey Maps
inside it so that I can manage them in one place.

**UX Notes:**
- URL: `/architectures/{id}`
- Page title: architecture title (editable inline)
- Sub-header: description (editable inline), status badge, kebab menu (rename, archive,
  delete)
- Body: tile grid of journey maps inside this architecture (same tile design as the
  existing journey map dashboard, US-DASH)
- Primary action: **"+ New Journey Map"** — calls `create_draft` with
  `journey_architecture_id`
- **"← Back to Architectures"** breadcrumb in header
- Loads via `GET /journey_architecture/{id}/bundle`

**Acceptance Criteria:**
- `GET /journey_architecture/{id}/bundle` called on mount; renders architecture +
  its maps
- Refreshing `/architectures/{id}` loads correctly without prior navigation
- "← Back to Architectures" navigates to `/architectures` and restores the tile list
- Empty map grid shows a "No maps yet" empty state with a "+ New Journey Map" CTA

---

### US-JA-14 — Rename / update a Journey Architecture

**Story:** As a user, I want to rename or update the description and status of an
architecture from either the dashboard tile or the detail view header.

**UX Notes:**
- Title is inline-editable on the tile (kebab → Rename) and in the detail view header
- Description is inline-editable in the detail view header
- Status change via kebab or status badge click (same pattern as map dashboard)

**Acceptance Criteria:**
- `PATCH /journey_architecture/{id}` called only when a value has actually changed
- Tile and detail view header update optimistically; revert on API failure with toast
- Whitespace-only titles are rejected and reverted

---

### US-JA-15 — Delete a Journey Architecture

**Story:** As a user, I want to delete a Journey Architecture (and all maps inside it)
from the dashboard so that I can clean up containers I no longer need.

**UX Notes:**
- "Delete" in tile kebab opens a **confirmation popover** anchored to the tile
- Copy: **"Delete '{architecture title}'?"** with subtext **"This will permanently remove
  the architecture and all journey maps, stages, lenses, and cells inside it.
  This cannot be undone."**
- Two buttons: **"Cancel"** and **"Delete"** (destructive/red)
- On confirm: tile fades out; empty state shown if no architectures remain

**Acceptance Criteria:**
- `DELETE /journey_architecture/{id}` called only after explicit confirmation
- Tile removed from local state immediately on API success
- Failed delete shows toast error and restores the tile

---

### US-JA-16 — Archive a Journey Architecture

**Story:** As a user, I want to archive an architecture I am done with so that it leaves
my active list but is not permanently deleted.

**UX Notes:**
- "Archive" in tile kebab sends `PATCH /journey_architecture/{id}` with
  `status: "archived"`
- Archived tiles are visually dimmed and sorted to the bottom of the grid
- "Unarchive" option appears in kebab for archived tiles

**Acceptance Criteria:**
- Archiving changes the status badge to Archived and moves tile to bottom
- Unarchiving restores status to `draft` and re-sorts tile by recency
- Both actions call `PATCH /journey_architecture/{id}` with correct status value

---

### US-JA-17 — Create a Journey Map inside an architecture

**Story:** As a user inside an architecture detail view, I want to create a new Journey
Map that automatically belongs to this architecture so that I don't have to manually
assign it.

**UX Notes:**
- "+ New Journey Map" button inside the detail view (US-JA-13)
- Calls `POST /journey_map/create_draft` with `journey_architecture_id`
- On success: new map tile appears at the top of the map grid inside the architecture
  AND navigates into the map editor

**Acceptance Criteria:**
- `create_draft` called with `journey_architecture_id` equal to the current architecture
- New map is scoped to the architecture; `GET /journey_map?journey_architecture_id={id}`
  returns it
- Navigation to the map editor happens only after successful API response
- Navigating back from the editor returns to `/architectures/{id}` (not the top-level
  dashboard)

---

## Implementation Sequence

```
Backend first:
US-JA-01 (table + FK migration) →
US-JA-02 (POST create) →
US-JA-03 (GET list) →
US-JA-04 (GET single) →
US-JA-05 (PATCH update) →
US-JA-06 (DELETE) →
US-JA-07 (GET bundle) →
US-JA-08 (update create_draft) →
US-JA-09 (update GET journey_map filter)

Frontend after backend is stable:
US-JA-10 (architecture tile grid) →
US-JA-11 (empty state) →
US-JA-12 (create architecture) →
US-JA-13 (detail view + map list) →
US-JA-14 (rename / update) →
US-JA-15 (delete with confirmation) →
US-JA-16 (archive / unarchive) →
US-JA-17 (create map inside architecture)
```

---

## Dependencies

- Existing `journey_map`, `journey_stage`, `journey_lens`, `journey_cell` tables are
  unchanged except for the nullable FK added in US-JA-01
- `journey_map/create_draft` (US-JA-08) and `GET /journey_map` (US-JA-09) are additive
  changes — all existing callers and tests remain valid
- Frontend US-JA-13 through US-JA-17 depend on Epic 8 (Journey Map Dashboard, US-DASH)
  tile components being available for reuse
- React Router must be in place for `/architectures/{id}` URL routing (already required
  by US-DASH-05)

---

## Phase 2 Preview (out of scope here)

Phase 2 will add a `journey_link` table to store directed connections between Journey Maps
within the same architecture — capturing which cell/stage triggers a break to an
anti-journey or sub-journey, along with the link type (`exception`, `anti_journey`,
`sub_journey`). The architecture bundle endpoint will be extended to include the link graph.
