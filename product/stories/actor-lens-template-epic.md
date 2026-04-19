## Actor Lens Template Epic

### Purpose

Give every journey row (lens) an actor identity — a typed role with a structured template that defines what to capture at both the row level and at each stage cell. When a user adds a new row, an Actor Setup Wizard fires to configure who this actor is and what template drives their cell fields. This grounds the AI agent per actor and ensures every row captures the right information for that role.

### Architecture Decision: Lens Level vs Cell Level

| Layer | What it captures | Persists on |
|---|---|---|
| **Lens level** | Who the actor IS across the whole journey | `journey_lens` table |
| **Cell level** | What the actor DOES/FEELS at each stage | `journey_cell.actor_fields` JSON |

#### Lens-level fields (actor identity — constant across all stages)

| # | Field | Key | Definition |
|---|---|---|---|
| 1 | Actor Type | `actor_type` | Enum: customer, operations, ai_agent, dev, custom |
| 2 | Template Key | `template_key` | Which template was applied (e.g. `customer-v1`) |
| 3 | Role Prompt | `role_prompt` | AI instructions for this actor — injected into agent context |
| 4 | Persona Description | `persona_description` | Who this specific actor is (e.g. "Residential homeowner, first-time buyer") |
| 5 | Primary Goal | `primary_goal` | Overarching Job-to-be-Done across the entire journey |
| 6 | Standing Constraints | `standing_constraints` | Fixed limitations this actor brings (schedule, access, budget) |

> **Rationale for fields 5 & 6:** "Problem / Job-to-be-Done" (original field #1) and "Customer Constraints" (original field #11) describe the actor across the whole journey, not a single stage — they belong at the lens level.

#### Cell-level fields (stage-specific — stored as `actor_fields` JSON on `journey_cell`)

| # | Field | Key | Definition |
|---|---|---|---|
| 1 | Entry Point / Trigger | `entry_trigger` | What caused the actor to arrive at this step |
| 2 | Feelings / Emotions | `emotions` | What the actor is feeling as they go through this step |
| 3 | Information Needs | `information_needs` | What they need to know to feel confident moving forward |
| 4 | Decisions Required | `decisions_required` | Choices they have to make at this step |
| 5 | Friction Points | `friction_points` | What could cause hesitation, confusion, or abandonment |
| 6 | Assumptions | `assumptions` | What they believe to be true that may or may not be accurate |
| 7 | Acceptance Criteria | `acceptance_criteria` | What success looks like for them at this step |
| 8 | Expected Output | `expected_output` | What they expect to receive or happen after completing this step |
| 9 | Channel / Touchpoint | `channel_touchpoint` | How or where this step is happening |

### Customer Template — `customer-v1`

The first fully defined template. Applied when `actor_type = customer`.

**Role Prompt (injected into AI agent context):**
> You are capturing the customer's perspective at each stage of this journey. For each stage focus on: Entry Trigger (what brought them here), Emotions (how they feel), Information Needs (what they need to know), Decisions Required (choices they must make), Friction Points (what could cause them to hesitate or abandon), Assumptions (what they believe that may be wrong), Acceptance Criteria (what success looks like), Expected Output (what they expect after this step), and Channel / Touchpoint (how or where this step happens). Be specific. Use the customer's language. Avoid internal jargon.

### Scope

- Backend schema additions to `journey_lens` and `journey_cell` tables
- Updated add-lens API to accept actor type and template, scaffold cell fields
- Frontend type definitions for actor fields
- Frontend constants: actor template registry (`ACTOR_TEMPLATES`)
- Actor Setup Wizard modal triggered when adding a new row
- AI agent receives actor role context per cell

### Explicit Non-Goals

- Other actor templates (operations, ai_agent, dev) are defined in a future epic
- Per-field access control or locking on actor fields
- Migrating existing lens rows to have actor types retroactively

---

### Epic: Actor Lens Templates

---

**US-ALT-01 — Add actor identity fields to the journey_lens schema**

**Story:** As a product operator, I want each journey lens row to carry an actor type, template reference, and role context so that every row has a clear identity before any cells are filled in.

**Acceptance Criteria:**
- The following columns are added to the `journey_lens` table, all optional:
  - `actor_type` enum — values: `customer`, `operations`, `ai_agent`, `dev`, `custom`
  - `template_key` text with `filters=trim`
  - `role_prompt` text with `filters=trim`
  - `persona_description` text with `filters=trim`
  - `primary_goal` text with `filters=trim`
  - `standing_constraints` text with `filters=trim`
- All fields are nullable — existing lens rows are unaffected
- `actor_type` defaults to `null` for legacy rows (no backfill required)

**Layer:** Backend — `tables/8_journey_lens.xs`

---

**US-ALT-02 — Add structured actor_fields to the journey_cell schema**

**Story:** As a product operator, I want each journey cell to optionally store structured actor-specific fields so that the cross-point of actor × stage captures the right data for each role.

**Acceptance Criteria:**
- A `actor_fields` JSON column is added to `journey_cell`, nullable
- The JSON schema for `actor_type = customer` contains keys: `entry_trigger`, `emotions`, `information_needs`, `decisions_required`, `friction_points`, `assumptions`, `acceptance_criteria`, `expected_output`, `channel_touchpoint` — all null by default
- Existing cells are unaffected (field is null unless explicitly set)
- The JSON is schema-less at the DB level; validation lives in the API layer

**Layer:** Backend — `tables/9_journey_cell.xs`

---

**US-ALT-03 — Update the add-lens API to accept actor type and apply template defaults**

**Story:** As the frontend, I want to pass an actor type and template key when creating a new lens row so that the backend applies the correct role prompt and scaffolds `actor_fields` on every new cell.

**Acceptance Criteria:**
- The `journey_lens/add/{journey_map_id}` POST endpoint accepts new optional fields: `actor_type`, `template_key`, `persona_description`, `primary_goal`, `standing_constraints`, `role_prompt`
- If `actor_type = customer` and no `role_prompt` is provided, the endpoint defaults to the `customer-v1` role prompt
- If `actor_type = customer` and no `template_key` is provided, it defaults to `customer-v1`
- New cells scaffolded for the lens have `actor_fields` populated with all 9 customer field keys set to `null` when `actor_type = customer`
- For other actor types or no actor type, `actor_fields` is `null` on new cells
- The API response `lens` object includes all new actor fields
- Existing behaviour (no actor_type passed) is fully backward-compatible

**Layer:** Backend — `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`

---

**US-ALT-04 — Update frontend type definitions for actor fields**

**Story:** As the frontend codebase, I need typed interfaces for actor fields so that the wizard, cell panel, and xano layer are type-safe.

**Acceptance Criteria:**
- `ActorType` union type added to `types.ts`: `'customer' | 'operations' | 'ai_agent' | 'dev' | 'custom'`
- `CustomerActorFields` interface added with all 9 cell-level field keys (`entry_trigger`, `emotions`, etc.), all `string | null`
- `ActorFields` type alias added as `CustomerActorFields | Record<string, string | null>`
- `Lens` interface updated with optional actor fields: `actorType`, `templateKey`, `rolePrompt`, `personaDescription`, `primaryGoal`, `standingConstraints`
- `MatrixCell` interface updated with optional `actorFields?: ActorFields | null`

**Layer:** Frontend — `webapp/protype-2/src/types.ts`

---

**US-ALT-05 — Update xano.ts interfaces and the addJourneyLens function**

**Story:** As the frontend API layer, I want `addJourneyLens` to accept the full actor setup input and map actor fields back from the backend response so the app state reflects actor identity.

**Acceptance Criteria:**
- `XanoJourneyLens` interface updated with: `actor_type`, `template_key`, `role_prompt`, `persona_description`, `primary_goal`, `standing_constraints` (all optional/nullable)
- `XanoJourneyCell` interface updated with `actor_fields?: Record<string, unknown> | null`
- `AddJourneyLensInput` type extended with: `actorType`, `templateKey`, `rolePrompt`, `personaDescription`, `primaryGoal`, `standingConstraints`
- `addJourneyLens` function passes all actor fields in the POST body (only non-empty values included)
- `buildHydratedJourneyMapBundle` maps actor fields from `XanoJourneyLens` onto the `Lens` objects returned to the app
- `buildHydratedJourneyMapBundle` maps `actor_fields` from `XanoJourneyCell` onto the `MatrixCell` objects

**Layer:** Frontend — `webapp/protype-2/src/xano.ts`

---

**US-ALT-06 — Add actor template registry to constants**

**Story:** As the frontend, I want a central `ACTOR_TEMPLATES` registry so that the wizard, type definitions, and API calls all draw from one source of truth.

**Acceptance Criteria:**
- `ActorTemplate` interface defined with: `actorType`, `templateKey`, `label`, `description`, `icon`, `rolePrompt`, `cellFieldScaffold`
- `ACTOR_TEMPLATES` array exported from `constants.ts` containing the `customer-v1` entry
- `customer-v1` entry includes the full role prompt, the 9-key `cellFieldScaffold` with all values `null`, label `"Customer"`, and a short description
- Other actor types (operations, ai_agent, dev) are listed as stub entries with `templateKey: null` and a `comingSoon: true` flag so the wizard can render them as disabled cards

**Layer:** Frontend — `webapp/protype-2/src/constants.ts`

---

**US-ALT-07 — Build the Actor Setup Wizard modal**

**Story:** As a user, when I click "Add Row" on the journey matrix I want an Actor Setup Wizard to appear so that I can define who this actor is before the row is created.

**Acceptance Criteria:**
- Clicking "Add Row" opens the Actor Setup Wizard modal instead of immediately adding a blank lens
- The wizard shows actor type selection cards: Customer (active), Operations, AI Agent, Dev, Custom (last four show "Coming Soon" badge and are disabled)
- Selecting an actor type pre-fills the `Label` field (e.g. "Customer") and shows the template's role prompt in a collapsed preview
- Three optional text fields are shown below the type selector: Persona Description, Primary Goal, Standing Constraints — each with placeholder examples
- A "Role Prompt Preview" collapsible shows the template's AI instructions (read-only)
- "Add Actor" confirm button is disabled until an actor type is selected
- "Cancel" closes the modal without creating a row
- On confirm, the wizard calls `addJourneyLens` with the full actor input and closes
- A loading state is shown on the confirm button while the API call is in flight
- Errors from the API surface inline in the wizard (not as a page-level banner)

**Layer:** Frontend — `webapp/protype-2/src/ActorSetupWizard.tsx` (new component)

---

**US-ALT-08 — Wire Actor Setup Wizard into App.tsx**

**Story:** As the app shell, I want the "Add Row" button to open the actor wizard and the wizard's confirm to trigger the full add-lens + refresh flow.

**Acceptance Criteria:**
- `showActorWizard` boolean state added to App
- "Add Row" button `onClick` sets `showActorWizard = true` instead of calling `addLens()` directly
- `addLens` function refactored to accept an `ActorWizardInput` parameter and pass it through to `addJourneyLens`
- `handleActorWizardConfirm(input)` handler: persists current cell, calls `addLens(input)`, closes wizard
- `<ActorSetupWizard>` rendered in the App JSX with `isOpen`, `onClose`, `onConfirm` wired up
- Existing refresh-after-add and error-handling behaviour is preserved

**Layer:** Frontend — `webapp/protype-2/src/App.tsx`

---

**US-ALT-09 — Inject actor role context into AI agent per cell**

**Story:** As the AI agent, I want to know the actor type, persona, and role prompt of the lens I am filling so that my responses reflect the correct actor perspective at each cell.

**Acceptance Criteria:**
- When the AI message API is called with a selected cell, the backend looks up the cell's parent lens and reads `actor_type`, `role_prompt`, `persona_description`, `primary_goal`, and `standing_constraints`
- Non-null actor fields are injected into the agent system prompt or context block before generation
- The prompt format is: `Actor: {label} ({actor_type}) — {persona_description}. Goal: {primary_goal}. Constraints: {standing_constraints}. Role instructions: {role_prompt}`
- Fields with null values are omitted from the prompt to avoid noise
- AI responses for customer rows use the customer's language and perspective, not operational language
- Injecting actor context does not break existing AI message flow when actor fields are absent

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

**US-ALT-10 — Edit actor details on an existing lens row (Save button)**

**Story:** As a user, I want to edit the actor identity fields on an existing lens row after it has been created so that I can refine the persona, goal, or constraints as the journey evolves, with an explicit Save button to confirm changes.

**Acceptance Criteria:**
- When a cell is selected and its parent lens has an `actor_type`, the Cell Detail Panel displays an **Actor** section showing: actor type badge, persona description, primary goal, and standing constraints
- An **Edit Actor** button within that section opens the Actor Setup Wizard in edit mode, pre-populated with the existing lens actor fields
- In edit mode the wizard title reads "Edit Actor" and the confirm button reads "Save Changes"
- Clicking "Save Changes" calls a new PATCH endpoint `journey_lens/actor_fields/{journey_lens_id}` with only the changed fields
- The PATCH endpoint accepts: `label`, `actor_type`, `template_key`, `role_prompt`, `persona_description`, `primary_goal`, `standing_constraints` — all optional; only provided fields are written
- The lens record in local app state is updated immediately after a successful save (optimistic-friendly)
- A loading indicator is shown on the "Save Changes" button while the PATCH is in flight
- Errors surface inline in the wizard, not as a page-level banner
- If a lens has no `actor_type` (legacy row), no Actor section is shown in the Cell Detail Panel

**New backend file:** `apis/journey_map/63_journey_lens_actor_fields_journey_lens_id_PATCH.xs`
**Frontend layers:** `webapp/protype-2/src/xano.ts` (`updateLensActorFields`), `ActorSetupWizard.tsx` (edit mode), `App.tsx` (Cell Detail Panel actor section + edit handler)
