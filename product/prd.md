## Emgram1010 Prototype 2 PRD

### Problem

Operational knowledge usually lives in the heads of domain experts, but current capture workflows are too linear, too unstructured, or too hard to validate. Notes and chat transcripts alone do not give teams a durable, stage-by-stage map of how work actually happens, where judgment changes, and which answers are confirmed versus inferred.

The product needs a faster way to capture expert knowledge inside a structured journey matrix while keeping the interview flow conversational. The immediate problem this prototype solves is how to let an operator or expert move fluidly between AI-guided questioning and direct matrix editing without losing context.

### User

- **Primary user:** Product operator, founder, researcher, or analyst building a journey map from expert input.
- **Secondary user:** Domain expert contributing workflow knowledge during an interview or review session.
- **Reviewer user:** Internal teammate reviewing which parts of the map are confirmed, drafted by AI, or still open.

Core job-to-be-done: **Help me capture and organize expert process knowledge into a structured journey map while preserving what is verified, what is inferred, and what still needs follow-up.**

### Solution

Build a matrix-first web app for expert knowledge capture with a dockable AI interviewer. The interface centers on a journey matrix where columns represent stages and rows represent lenses. Users can build, inspect, and refine the map while the AI interviewer asks questions and suggests updates.

Current prototype behavior indicates the product should include:

1. **Journey matrix workspace**
   - Default structure starts with 8 stages and 10 lenses.
   - Stages and lenses are editable by label.
   - Users can add or remove columns and rows.
   - Each matrix cell stores structured content tied to a specific stage/lens intersection.

2. **Verification-aware cell model**
   - Every cell has one of three statuses: `confirmed`, `draft`, or `open`.
   - Users can update status from a dedicated detail panel.
   - The interface surfaces rollup counts for confirmed, draft, and open cells.

3. **Cell detail editing and protection**
   - Selecting a cell opens a right-side detail panel.
   - Users can directly edit cell content.
   - Users can lock a cell to prevent AI-driven changes.
   - Locked state must be visible and understandable.

4. **AI interviewer sidebar**
   - Users can open a dedicated AI panel from the workspace.
   - The AI supports an interview-style workflow and a general chat-style workflow.
   - Messages are shown as a conversation between expert and AI.
   - Suggested prompt chips help users continue the session quickly.
   - In interview mode, AI responses may update eligible matrix cells.
   - In chat mode, conversation should not silently overwrite the matrix.

5. **Findability and orientation**
   - Users can search the matrix.
   - The UI shows the current map context, selected cell context, and matrix legend.
   - The product should remain legible for dense workflow mapping work.

6. **Prototype-level non-goals for this version**
   - No requirement yet for multi-user collaboration.
   - No requirement yet for persistence, sync, or backend storage.
   - No requirement yet for export, import, or downstream scenario generation in-app.
   - No requirement yet for production-grade AI accuracy; current prototype behavior is enough to validate interaction design.

### Constraints

#### Hard Constraints
- The core interaction model must remain a **stage-by-lens matrix**, not a chat-only flow.
- Users must be able to distinguish **expert-confirmed**, **AI-drafted**, and **open-question** content at the cell level.
- Users must be able to manually override AI suggestions.
- Locked cells must not be modified by AI-assisted updates.
- The experience must support both **conversational capture** and **direct matrix editing** in the same workspace.
- The interface must stay usable for non-technical subject-matter experts and operators.

#### Soft Constraints
- Keep the default structure lightweight enough to scan quickly.
- Prefer a desktop-first layout with persistent side panels over modal-heavy flows.
- Preserve a clean, low-noise visual design so the matrix stays readable.
- Make progress visible through counts, status indicators, and contextual side panels.

### Success Metrics

- A user can create or refine a journey map without leaving the main workspace.
- A user can identify the state of any cell (`confirmed`, `draft`, `open`) at a glance.
- A user can select a cell, edit it, set its verification state, and lock it in under 15 seconds.
- A user can add/remove stages and lenses without breaking the matrix structure.
- In moderated testing, users understand the difference between **Interview Mode** and **Chat Mode** without explanation.
- During pilot usage, the team can complete a first-pass journey map faster than with an unstructured transcript-plus-spreadsheet workflow.

### Risks

1. **AI trust ambiguity**
   - Risk: users may over-trust AI-generated drafts if the difference between inferred and confirmed data is not clear enough.
   - Mitigation: keep status labeling prominent and require easy manual verification changes.

2. **Schema sprawl**
   - Risk: allowing custom rows and columns can make maps inconsistent and harder to compare.
   - Mitigation: start from a strong default schema and treat customization as lightweight extension, not a blank canvas.

3. **Context switching friction**
   - Risk: users may feel split between the matrix, detail panel, and AI sidebar.
   - Mitigation: preserve strong context cues, minimize hidden state changes, and ensure each panel has a clear role.

### Open Questions

- What should trigger an automatic AI matrix update versus a suggested-but-unapplied change?
- What exact behaviors should differ between Interview Mode and Chat Mode beyond matrix updates?
- What persistence model is needed first: local draft save, backend save, or export?
- Which matrix lenses are mandatory in v1 and which should be removable or optional?
- Should the product optimize for expert self-service, operator-led interviews, or both equally?
- What audit trail is needed so users can see who changed a cell and why?