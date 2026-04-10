## Conversational AI Agent Enablement Epic

### Purpose

Define the epic and implementation-ready user stories required to enable a conversational AI agent that can guide interviews, support freeform chat, and safely interact with the journey map workspace.

### Scope for this epic

- Support both `interview` and `chat` modes
- Ground AI responses in journey map context, selected cell context, and conversation history
- Allow structured AI-proposed or AI-applied matrix updates in the right mode
- Preserve trust through lock rules, attribution, and visible status handling
- Return a frontend-friendly response contract for chat content, prompt suggestions, and structured updates

### Explicit non-goals for this phase

- Voice input/output or multimodal interaction
- Autonomous agent actions outside the journey map workflow
- Production-grade model evaluation, fine-tuning, or cost optimization
- Multi-user agent collaboration or role-specific agent personas

### Epic 1: Enable the conversational AI agent

**US-01 — Define the agent interaction contract**
- **Story:** As a product team, we want a clear backend contract for the conversational AI agent so that frontend and backend can reliably support both chat and interview workflows.
- **Acceptance Criteria:**
  - The AI request accepts journey map context, selected cell context, conversation history, and a `mode` flag.
  - The AI response returns assistant message content in a stable shape.
  - The response can optionally include structured cell updates and suggested follow-up prompts.
  - The response shape distinguishes between conversational output and matrix mutation output.
- **Recommended agent:** AI Orchestration Engineer

**US-02 — Build agent context assembly**
- **Story:** As the AI system, I want relevant map and conversation context assembled before generation so that responses stay grounded in the current workflow.
- **Acceptance Criteria:**
  - Prompt assembly includes journey map title, stages, lenses, selected cell details, and recent conversation history.
  - Locked cells and current cell statuses are available to the agent as context.
  - Context size is constrained to a predictable window to avoid unbounded payload growth.
  - Missing optional context does not break the AI request flow.
- **Recommended agent:** AI Orchestration Engineer

**US-03 — Support conversational chat responses**
- **Story:** As a user, I want to ask the AI freeform questions about the workflow so that I can explore, clarify, and refine ideas without directly changing the matrix.
- **Acceptance Criteria:**
  - In `chat` mode, the AI returns a conversational response only.
  - Chat responses do not silently mutate any matrix cell.
  - The response can include suggested follow-up prompts for the sidebar.
  - Errors are returned in a frontend-safe way for display to the user.
- **Recommended agent:** AI Orchestration Engineer

**US-04 — Support interview-driven matrix updates**
- **Story:** As a user in interview mode, I want the AI to turn conversational findings into structured journey map updates so that the matrix fills in as the session progresses.
- **Acceptance Criteria:**
  - In `interview` mode, the AI can return one or more structured cell updates.
  - Each proposed update identifies its target by stage and lens or by canonical cell identifier.
  - AI-written cell content is marked with source `ai`.
  - AI-written updates default to `draft` unless explicitly confirmed later by the user.
- **Recommended agent:** AI Orchestration Engineer

**US-05 — Enforce matrix safety and trust rules**
- **Story:** As a reviewer, I want strong safety rules around AI updates so that the agent cannot overwrite protected or user-confirmed information unexpectedly.
- **Acceptance Criteria:**
  - Locked cells are never modified by AI-applied updates.
  - The system returns which requested updates were applied, skipped, or rejected.
  - Invalid or ambiguous targets are rejected without partial corruption of cell data.
  - Confirmed user content is not downgraded or overwritten without an explicit rule.
- **Recommended agent:** Backend Engineer

**US-06 — Persist conversational sessions and AI actions**
- **Story:** As a user, I want AI conversations and resulting actions saved with the journey map so that I can resume work with full context and auditability.
- **Acceptance Criteria:**
  - User and assistant messages are stored with `role`, `content`, timestamp, and mode.
  - AI-applied cell changes are stored with change source metadata.
  - A saved journey map can return recent conversation history alongside matrix state.
  - The system preserves ordering of messages within a conversation thread.
- **Recommended agent:** Backend Engineer

**US-07 — Connect the frontend AI sidebar to the agent contract**
- **Story:** As a user, I want the AI sidebar to send and render conversational agent interactions so that the workspace feels like one continuous interview and editing experience.
- **Acceptance Criteria:**
  - Sending a sidebar message calls the AI endpoint with the active mode and current context.
  - Assistant replies render in the conversation timeline.
  - Suggested prompts can be shown as clickable continuation chips.
  - Structured updates returned in `interview` mode are reflected in the matrix and detail panel state.
- **Recommended agent:** Frontend Engineer

**US-08 — Add smoke coverage for conversational agent behavior**
- **Story:** As the team shipping the agent, we want validation coverage for key conversational workflows so that future changes do not break the AI-assisted experience.
- **Acceptance Criteria:**
  - Tests or smoke checks cover chat response flow, interview response flow, locked-cell protection, and conversation persistence.
  - Validation confirms that `chat` mode does not mutate cells.
  - Validation confirms that `interview` mode can return structured updates in the expected schema.
  - Failures make it clear whether the issue is prompt assembly, backend contract, or frontend rendering.
- **Recommended agent:** Eval/Test Engineer

---

### Suggested first build slice

Build in this order: `US-01 -> US-02 -> US-03 -> US-04 -> US-05 -> US-07 -> US-06 -> US-08`.

This gives the team the smallest useful conversational agent loop: a stable contract, grounded responses, interview-mode updates, safety controls, frontend wiring, and lightweight validation.