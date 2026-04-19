# Lens Header Edit Button Epic

## Goal
Allow users to edit the actor role (type, persona, goal, constraints) directly from the lens row header in the journey matrix — without needing to open a cell first. A hover edit button on each lens row opens the Actor Setup Wizard in edit mode.

---

## Stories

### US-LHE-01 — Update `formatLensCellMarkup` helper
**File:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts`

**Story:** As a user, I want the lens row header to show the actor type and a hover edit icon so I can see the role at a glance and jump directly into editing it.

**Changes:**
- Change signature from `(value: unknown)` to `({ label, actorType, lensId }: { label: string; actorType?: string; lensId?: string })`
- Render an actor type pill (`.jm-lens-actor-pill`) when `actorType` is set
- Render a pencil edit button (`.jm-lens-edit-btn`) with `data-edit-lens-id="{lensId}"` — hidden by default, shown on group hover
- Update the single call site in `JourneyMatrixTabulator.tsx` to pass the new shape

**AC:**
- Lens cells with an actor type show a small pill label (e.g. "customer")
- Hovering the lens cell reveals the pencil edit icon
- The edit button carries `data-edit-lens-id` with the lens row id

---

### US-LHE-02 — Add `onEditLens` prop and click delegation to `JourneyMatrixTabulator`
**File:** `webapp/protype-2/src/JourneyMatrixTabulator.tsx`

**Story:** As a developer, I want `JourneyMatrixTabulator` to detect edit-button clicks and fire a callback so that `App.tsx` can open the Actor Setup Wizard without the component knowing about wizard state.

**Changes:**
- Add `onEditLens: (lensId: string) => void` to the `Props` type
- Add `onEditLensRef` to avoid stale closure issues
- Add `lensActorType` to each `tableData` row (from `lens.actorType`)
- Update the `lensLabel` column formatter to call `formatLensCellMarkup({ label, actorType, lensId })`
- Remove `editor: 'input'` from the lens column (label editing now handled by the wizard)
- In the existing container `click` handler, intercept clicks on `[data-edit-lens-id]` elements: stop propagation, call `onEditLensRef.current(lensId)`, return early

**AC:**
- Clicking the edit button calls `onEditLens` with the correct lens id string
- Clicking a regular matrix cell still calls `onSelectCell` as before
- No Tabulator inline editor fires on the lens column

---

### US-LHE-03 — Wire `onEditLens` in `App.tsx`
**File:** `webapp/protype-2/src/App.tsx`

**Story:** As a user, clicking the edit icon on a lens row header opens the Actor Setup Wizard pre-populated with that lens's current actor identity so I can update it.

**Changes:**
- Add `handleLensEditFromMatrix` handler: looks up the lens by id in the `lenses` array, calls `handleEditActorOpen(lens)`
- Pass `onEditLens={handleLensEditFromMatrix}` to `<JourneyMatrixTabulator />`

**AC:**
- Clicking the edit icon on a lens row header opens the Actor Setup Wizard in edit mode
- The wizard is pre-populated with the lens's current label, actor type, persona, goal, and constraints
- Saving in the wizard patches the lens and refreshes the map

---

### US-LHE-04 — CSS for lens header hover, edit button, and actor type pill
**File:** `webapp/protype-2/src/index.css`

**Story:** As a user, the lens header cell should have a clean hover state with a subtly visible edit icon and a small actor type label so the UI stays uncluttered but discoverable.

**Changes:**
- Make `.jm-lens-cell` `position: relative` and add `group` hover support
- Add `.jm-lens-edit-btn` — absolutely positioned pencil icon, hidden by default, shown on `.jm-lens-cell:hover`
- Add `.jm-lens-actor-pill` — small pill showing actor type (e.g. "customer"), muted styling
- Edit button uses a pencil SVG inline or unicode pencil `✎`

**AC:**
- Edit button is invisible when not hovering
- Edit button appears clearly on hover
- Actor type pill is always visible (if actor type is set)
- No layout shift on hover
