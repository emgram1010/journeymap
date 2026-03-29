## Emgram1010 Prototype 2 Backend + Frontend Integration User Stories

### Purpose

Translate `product/prd.md` into implementation-ready user stories for building the backend and connecting it to the existing `webapp/protype-2` frontend.

### Scope for this story set

- Persist journey map drafts
- Persist stages, lenses, cells, and chat history
- Support Interview Mode and Chat Mode behavior
- Support AI-assisted cell updates with lock protection
- Replace local mock data in the frontend with backend-backed state

### Explicit non-goals for this phase

- Multi-user collaboration
- Permissions beyond a simple prototype-safe access model
- Export to Google Sheets or downstream scenario generation
- Production-grade analytics or billing

### Recommended implementation sequence

1. Data model
2. Read/write APIs
3. AI orchestration APIs
4. Frontend data integration
5. Validation and smoke testing

---

### Epic 1: Journey map persistence foundation

**US-01 — Create the core journey map schema**
- **Story:** As a product operator, I want a backend data model for journey maps, stages, lenses, cells, conversations, and messages so that the frontend can save and reload work instead of relying on local mock state.
- **Acceptance Criteria:**
  - A journey map record can be created with title and draft status.
  - Stages and lenses are stored as ordered records tied to a journey map.
  - Cells are stored by `journey_map_id + stage_id + lens_id`.
  - Each cell stores `content`, `status`, `is_locked`, and timestamps.
  - Conversations and messages can be linked to a journey map.
- **Recommended agent:** Xano Table Designer

**US-02 — Create a new draft journey map**
- **Story:** As a product operator, I want to create a new empty journey map with default stages and lenses so that I can start from the same structure shown in Prototype 2.
- **Acceptance Criteria:**
  - A create endpoint returns a new journey map with default 8 stages and 10 lenses.
  - Default cells are created in `open` state.
  - The response shape is usable by the existing React app without extra manual reshaping.
- **Recommended agent:** Xano API Query Writer

**US-03 — Load an existing journey map into the frontend**
- **Story:** As a user reopening work, I want the frontend to fetch a saved journey map and its related records in one request so that the matrix loads with complete context.
- **Acceptance Criteria:**
  - A read endpoint returns journey map metadata, stages, lenses, cells, and recent conversation history.
  - Returned stages and lenses preserve display order.
  - Returned cells include status and lock state.
  - The frontend can hydrate its state from the response on first load.
- **Recommended agent:** Xano API Query Writer

---

### Epic 2: Matrix editing APIs

**US-04 — Update stage and lens labels**
- **Story:** As a user shaping the map, I want to rename stages and lenses so that the matrix matches the workflow being documented.
- **Acceptance Criteria:**
  - A stage label can be updated independently.
  - A lens label can be updated independently.
  - Updated labels are returned immediately to the frontend.
  - Empty or invalid labels are rejected with user-friendly errors.
- **Recommended agent:** Xano API Query Writer

**US-05 — Add and remove stages and lenses**
- **Story:** As a user, I want to add or remove rows and columns so that the map can fit different workflows.
- **Acceptance Criteria:**
  - Adding a stage creates a new ordered stage plus matching cells for all existing lenses.
  - Adding a lens creates a new ordered lens plus matching cells for all existing stages.
  - Removing a stage also removes its cells.
  - Removing a lens also removes its cells.
  - The backend prevents deletion when it would violate a minimum required structure.
- **Recommended agent:** Xano API Query Writer

**US-06 — Edit cell content, status, and lock state**
- **Story:** As a user reviewing the matrix, I want to update a cell's content, verification status, and lock state so that the saved map reflects my decisions.
- **Acceptance Criteria:**
  - A cell can be updated for content only, status only, lock only, or all at once.
  - Allowed statuses are limited to `confirmed`, `draft`, and `open`.
  - Locked state is persisted and returned on future reads.
  - Updated cell data is returned in the write response.
- **Recommended agent:** Xano API Query Writer

**US-07 — Preserve a lightweight change history**
- **Story:** As a reviewer, I want basic change metadata on saved records so that I can understand what changed most recently.
- **Acceptance Criteria:**
  - Journey maps and cells track created and updated timestamps.
  - Cell updates track whether the change source was `user` or `ai`.
  - The frontend can display last-updated information if needed.
- **Recommended agent:** Xano Function Writer + Xano API Query Writer

---

### Epic 3: Conversation and AI behavior

**US-08 — Persist AI conversation threads**
- **Story:** As a user, I want the AI sidebar conversation saved with the journey map so that I can resume the same working session later.
- **Acceptance Criteria:**
  - Messages are stored with `role`, `content`, timestamp, and mode context.
  - A journey map can return its most recent conversation thread.
  - New messages can be appended without overwriting existing history.
- **Recommended agent:** Xano Table Designer + Xano API Query Writer

**US-09 — Support Interview Mode vs Chat Mode on the backend**
- **Story:** As a user, I want backend AI actions to respect whether I am interviewing or chatting so that matrix updates only happen when appropriate.
- **Acceptance Criteria:**
  - The AI endpoint accepts a mode flag.
  - In `chat` mode, the response returns message content but no direct cell mutation.
  - In `interview` mode, the response may include one or more proposed cell updates.
  - Locked cells are excluded from AI-applied updates.
- **Recommended agent:** Xano Function Writer + Xano API Query Writer

**US-10 — Save AI-applied updates safely**
- **Story:** As a reviewer, I want AI-generated cell updates saved with clear attribution so that AI assistance never hides what was machine-drafted.
- **Acceptance Criteria:**
  - AI-written cell changes are stored with source `ai`.
  - AI-written cells default to `draft` unless explicitly confirmed by the user later.
  - If a targeted cell is locked, the backend skips the mutation and returns that it was skipped.
- **Recommended agent:** Xano Function Writer + Xano API Query Writer

---

### Epic 4: Frontend integration with the Xano backend

**US-11 — Replace mock initialization with backend load**
- **Story:** As a frontend user, I want the app to load from backend data on startup so that the matrix and chat represent real saved work.
- **Acceptance Criteria:**
  - The React app fetches a journey map on load.
  - Local mock seed data is removed or used only as explicit fallback/dev scaffolding.
  - Loading and error states are visible to the user.
- **Recommended agent:** Xano Frontend Developer

**US-12 — Save matrix edits from the frontend**
- **Story:** As a user editing the matrix, I want frontend actions to call backend write endpoints so that edits persist immediately.
- **Acceptance Criteria:**
  - Renaming a stage or lens triggers the correct API call.
  - Adding/removing a stage or lens triggers the correct API call.
  - Editing content, status, or lock state in the detail panel triggers the correct API call.
  - The UI updates optimistically or refreshes safely after save.
- **Recommended agent:** Xano Frontend Developer

**US-13 — Connect the AI sidebar to persisted chat and AI endpoints**
- **Story:** As a user, I want messages sent in the sidebar to go through the backend so that the conversation and any AI-generated map updates are durable.
- **Acceptance Criteria:**
  - Sending a message creates a persisted expert message.
  - The frontend requests an AI response through the backend.
  - In interview mode, returned AI updates are reflected in the matrix.
  - In chat mode, returned AI messages appear in chat without silently mutating cells.
- **Recommended agent:** Xano Frontend Developer

**US-14 — Keep frontend state aligned with backend truth**
- **Story:** As a user, I want the UI to stay consistent after save operations so that counts, selected cell state, lock state, and statuses never drift from the backend.
- **Acceptance Criteria:**
  - Confirmed/draft/open counts update after writes.
  - Selected cell details reflect the latest saved response.
  - Failed writes show an error and do not leave the UI in an ambiguous state.
  - Search still works against the latest loaded matrix data.
- **Recommended agent:** Xano Frontend Developer

---

### Epic 5: Quality and validation

**US-15 — Add backend workflow tests for core APIs**
- **Story:** As the team shipping this prototype, we want automated tests for critical backend flows so that core data operations remain safe while the schema evolves.
- **Acceptance Criteria:**
  - Tests cover create, load, edit cell, rename stage/lens, add/remove stage/lens, and AI update behavior.
  - Tests verify locked cells cannot be changed by AI.
  - Tests verify chat mode does not mutate cells.
- **Recommended agent:** Xano Unit Test Writer

**US-16 — Add frontend smoke coverage for the integrated flow**
- **Story:** As the team validating the integrated product, we want a smoke test checklist or lightweight automated flow so that we can confirm the app still works end-to-end after wiring in the backend.
- **Acceptance Criteria:**
  - The team can validate load, select cell, edit/save, change status, lock cell, send chat message, and send interview message.
  - Failures clearly identify whether the issue is frontend, API contract, or AI orchestration.
- **Recommended agent:** Xano Frontend Developer + Xano Unit Test Writer

---

### Suggested first build slice

Build in this order: `US-01 -> US-02 -> US-03 -> US-06 -> US-11 -> US-12 -> US-08 -> US-09 -> US-13`.

This gives you the smallest useful integrated version: saved journey maps, editable cells, persisted chat, and backend-controlled interview behavior.