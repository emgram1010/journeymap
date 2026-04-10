## Emgram1010 Prototype 2 Cell Identifiers Epic

### Purpose

Define a stable cell reference model so users, the AI agent, and the backend can identify, explain, and safely mutate the same journey-map cell without ambiguity.

### Scope for this story set

- Define canonical machine-readable cell identity
- Define user-facing cell references
- Resolve user and AI references safely
- Preserve reference stability across rename/add/remove flows
- Add validation and test coverage for cell targeting behavior

### Explicit non-goals for this phase

- Multi-user collaboration semantics
- Full audit-history redesign beyond existing change metadata
- Spreadsheet import/export compatibility for cell references
- Public API versioning beyond the current prototype

### Recommended implementation sequence

1. Canonical identity contract
2. User-facing reference display
3. Selected-cell AI context
4. Explicit reference resolution and ambiguity handling
5. Structural resilience and validation coverage

---

### Epic 1: Stable cell identifiers for human + AI collaboration

**US-CI-01 — Define canonical cell identity for persisted and local cells**
- **Story:** As the system, I want each journey-map cell to have a stable canonical identity so that frontend state, backend writes, and AI updates all target the same record safely.
- **Acceptance Criteria:**
  - Persisted cells are canonically identified by `journey_cell_id`.
  - AI and backend payloads include `journey_map_id`, `stage_id`, `lens_id`, `stage_key`, and `lens_key` for fallback resolution.
  - The frontend can reconcile updates by `journey_cell_id` first and semantic fallback second.
  - The contract distinguishes display labels from canonical identifiers.
- **Recommended agent:** Xano Table Designer + Xano API Query Writer + Xano Frontend Developer

**US-CI-02 — Add a user-facing cell reference format**
- **Story:** As a user, I want each selected cell to expose a clear human-readable reference so that I can discuss it with the AI without confusion.
- **Acceptance Criteria:**
  - The primary visible cell reference is `Stage Label × Lens Label`.
  - The selected-cell UI shows this reference in the detail panel or context area.
  - An optional compact shorthand such as `B2` or `S2-L4` can be shown as secondary context.
  - Raw database IDs are not shown as the primary user-facing identifier.
- **Recommended agent:** Xano Frontend Developer

**US-CI-03 — Support selected-cell referencing in the AI workflow**
- **Story:** As a user, I want to refer to "this cell" or the selected cell when chatting with the AI so that I do not need to restate the full context every time.
- **Acceptance Criteria:**
  - When a cell is selected, the AI request includes selected-cell context.
  - The selected-cell payload includes canonical identifiers and human-readable labels.
  - The AI can respond using the human-readable reference for the selected cell.
  - If no cell is selected, the system does not imply a target cell.
- **Recommended agent:** Xano Frontend Developer + Xano Function Writer

**US-CI-04 — Resolve explicit user references to the correct cell**
- **Story:** As the system, I want to resolve user references like `Booking × Customer Notification` or `B2` to the correct canonical cell so that the AI never writes to the wrong location.
- **Acceptance Criteria:**
  - The system resolves cell references within the scope of a single `journey_map_id`.
  - Resolution prefers canonical IDs, then stable keys, then human-readable context, then optional shorthand.
  - If a reference is ambiguous, the system asks for clarification instead of guessing.
  - If a reference cannot be resolved, the system returns a user-friendly explanation.
- **Recommended agent:** Xano Function Writer + Xano API Query Writer + Xano Frontend Developer

**US-CI-05 — Return AI updates with structured target metadata**
- **Story:** As a user, I want AI-proposed or AI-applied updates to name the exact targeted cell so that I can understand what changed and why.
- **Acceptance Criteria:**
  - Every proposed, applied, or skipped AI update returns `journey_cell_id`, `journey_map_id`, `stage_id`, `stage_key`, `stage_label`, `lens_id`, `lens_key`, and `lens_label`.
  - AI responses shown in the UI reference the target cell using `Stage Label × Lens Label`.
  - Skipped updates include a reason such as `locked`, `ambiguous`, `deleted`, or `not_found`.
  - The frontend can render these updates without requiring additional lookup calls.
- **Recommended agent:** Xano Function Writer + Xano API Query Writer + Xano Frontend Developer

**US-CI-06 — Keep cell references resilient through rename and structure changes**
- **Story:** As the system, I want cell references to remain safe even when stages and lenses are renamed, added, removed, or reordered so that human-facing labels can change without breaking machine targeting.
- **Acceptance Criteria:**
  - Renaming a stage or lens updates display labels without changing canonical persisted cell identity.
  - Machine targeting does not rely on labels alone.
  - Optional shorthand references are treated as convenience references, not canonical write targets.
  - When structural changes invalidate a previous shorthand or human reference, the system re-resolves or asks for clarification.
- **Recommended agent:** Xano API Query Writer + Xano Function Writer + Xano Frontend Developer

**US-CI-07 — Strengthen integrity rules for cell uniqueness and lookup safety**
- **Story:** As the team shipping AI-assisted editing, we want the data model and API behavior to guarantee safe one-cell targeting so that duplicate or conflicting matches do not undermine reliability.
- **Acceptance Criteria:**
  - The system enforces one logical cell per `journey_map + stage + lens`.
  - Stage keys and lens keys remain stable enough to support semantic fallback lookup.
  - Error handling is defined for deleted, stale, or conflicting targets.
  - API responses make stale-target failures understandable to the frontend.
- **Recommended agent:** Xano Table Designer + Xano API Query Writer

**US-CI-08 — Add validation and smoke coverage for cell reference behavior**
- **Story:** As the team validating the product, we want automated coverage for cell reference behavior so that user and AI targeting remains safe as the matrix evolves.
- **Acceptance Criteria:**
  - Tests cover selected-cell AI context, explicit human-readable references, ambiguity handling, and fallback resolution.
  - Tests verify locked-cell, confirmed-cell, and chat-vs-interview safeguards still work with structured cell references.
  - Tests verify rename, add, and remove flows do not break canonical targeting.
  - Smoke coverage confirms the UI displays the selected cell reference and AI responses reference the expected cell.
- **Recommended agent:** Xano Unit Test Writer + Xano Frontend Developer

---

### Suggested first build slice

Build in this order: `US-CI-01 -> US-CI-02 -> US-CI-03 -> US-CI-05 -> US-CI-04 -> US-CI-06 -> US-CI-07 -> US-CI-08`.

This gives you the smallest safe integrated version: stable machine identity, clear user-visible references, AI targeting that works with selected-cell context, and validation around ambiguity and structural changes.