## Implementation & QA Testing Strategy

### Why hybrid testing — not pure story-level or pure epic-level

Epic 2 contains three categories of change, each with different testability characteristics. Prompt-only changes are **non-deterministic** (LLM output varies), so they can't be asserted with exact-match workflow tests. Schema and frontend changes are **deterministic** and testable per story. This drives a hybrid approach.

### Testing by phase

| Phase | Stories | Implement as | Test as | Why |
|-------|---------|--------------|---------|-----|
| 1 — Prompt | 2.01, 2.07 | Single commit, one file | **Phase-level** simulation (5–10 scenarios) | Output format + quality gate are interdependent; testing one without the other gives misleading results |
| 2 — Schema | 2.03, 2.04, 2.05, 2.08 | Per-story commits | **Story-level** workflow tests | Each story has deterministic inputs/outputs |
| 2 — Prompt (depends on schema) | 2.06 | With 2.05 | **Phase-level** simulation (re-run Phase 1 scenarios) | Probing strategies require lens descriptions to be injected first |
| 3 — Frontend | 2.02 | Story-level commit | **Story-level** unit + Playwright | Standard component, deterministic rendering |
| 3 — Validation | 2.09 | After all others | **Epic-level** full regression | Final pass confirming everything works together |

### Phase 1 QA — Prompt simulation suite (2.01 + 2.07)

Prompt changes all edit `agents/2_journey_map_assistant.xs`. Run 5–10 scripted conversations and evaluate heuristically:

- **Vague answerer:** Send one-word answers → AI should probe deeper, NOT write to cell
- **Detailed answerer:** Send specific, multi-detail answers → AI should write cell AND reply under ~80 words
- **"Just write it" override:** Send vague answer, then "just write it" → AI should write as-is
- **Info dumper:** Send a long paragraph → AI should extract and write, short confirmation reply
- **Mode switcher:** Alternate interview/chat → chat should never mutate cells

Pass criteria are heuristic, not exact-match: replies *generally* under 60–80 words, quality gate triggers *most* of the time on vague inputs.

### Phase 2 QA — Schema workflow tests (2.03, 2.04, 2.05, 2.08)

Each story gets a deterministic workflow test:

- **2.03:** Create a lens → verify `description` field exists and is nullable
- **2.04:** Call `create_draft` → assert all 10 lenses have non-null `description` values matching expected definitions
- **2.05:** Call `ai_message` → verify the dynamic context string includes lens descriptions (log or return `$dynamic_context`)
- **2.08:** Create map → null out descriptions → call backfill endpoint → verify descriptions are populated, run twice to confirm idempotency

### Phase 3 QA — Frontend + epic regression (2.02, 2.09)

- **2.02:** Unit test: mock response with `cell_updates` → verify chip renders. Playwright: verify chip visible after real AI interaction, invisible when no cells updated.
- **2.09:** Full regression — all Phase 1 simulations re-run with lens descriptions now active, all Phase 2 workflow tests pass, all Epic 1 tests still pass.

---

## AI Agent Implementation Instructions (for new chat sessions)

> **How to use:** Start a new chat session per phase. Paste the phase heading below as your first message. The agent should read this file first, then the listed files, before making any changes.

### Phase 1 — Prompt rewrite (US-AI-2.01 + US-AI-2.07)

**Scope:** Rewrite the system prompt in a single file. Zero schema or frontend changes.

**Start by reading these files (in order):**
1. `product/stories/scalable-ai-agent-epic-2.md` — this file, for full story acceptance criteria
2. `agents/2_journey_map_assistant.xs` — the agent definition with the current system prompt to rewrite
3. `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — the orchestrator that injects dynamic context (understand what the agent already receives)
4. `product/stories/scalable-ai-agent-epic.md` — Epic 1 context for what already works

**What to change:**
- In `agents/2_journey_map_assistant.xs`, replace the `## Output format` section with a brevity-enforced version (<60 words, ban inline stats, ban listing cell writes, include good/bad example)
- In the same file, add a new `## Answer quality gate (Interview mode only)` section before Output format with per-lens minimum thresholds (see US-AI-2.07 acceptance criteria)

**What NOT to change:**
- Do not touch the orchestrator, schema, or frontend
- Do not modify the Interview mode rules or Chat mode rules sections (those are correct)
- Do not change the tools list

**QA after implementation:**
- Test via `POST /journey_map/{id}/ai_message` with the 5 simulation scenarios listed in the testing strategy above
- Heuristic pass: replies generally under 80 words, quality gate probes on vague input, "just write it" overrides gate

---

### Phase 2 — Schema + orchestrator + probing (US-AI-2.03, 2.04, 2.05, 2.06, 2.08)

**Scope:** Add lens `description` field, populate defaults, inject into AI context, add probing strategies, build backfill endpoint.

**Start by reading these files (in order):**
1. `product/stories/scalable-ai-agent-epic-2.md` — this file, for full story acceptance criteria
2. `tables/8_journey_lens.xs` — lens table schema (add `description` field here)
3. `apis/journey_map/42_journey_map_create_draft_POST.xs` — create_draft endpoint (add descriptions to lens seeds here)
4. `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — orchestrator (update lens injection block, lines ~122-128)
5. `agents/2_journey_map_assistant.xs` — agent prompt (add probing strategies section, should already have Phase 1 changes)
6. `workflow_tests/5_journey_map_ai_agent_tools.xs` — existing agent tool tests (reference for writing new workflow tests)

**What to change (in order):**
1. **2.03:** `tables/8_journey_lens.xs` — add `text description? filters=trim` field
2. **2.04:** `apis/journey_map/42_journey_map_create_draft_POST.xs` — add `description` to each of the 10 lens seed objects (see US-AI-2.04 for exact definitions)
3. **2.05:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — update the `foreach ($lenses)` block to include description when non-null: format as `"- **Label** (key): description"` instead of `"Label (key)"`
4. **2.06:** `agents/2_journey_map_assistant.xs` — add `## Interview probing strategies per lens type` section with 10 lens-specific question patterns
5. **2.08:** New endpoint `apis/journey_map/` — `POST /journey_lens/backfill_descriptions` that populates null descriptions on known default keys

**QA after implementation:**
- Workflow test per story (see Phase 2 QA section above)
- Re-run Phase 1 simulations — probing should now be domain-specific

---

### Phase 3 — Frontend + epic validation (US-AI-2.02, US-AI-2.09)

**Scope:** Add progress chip component to chat, run full epic regression.

**Start by reading these files (in order):**
1. `product/stories/scalable-ai-agent-epic-2.md` — this file
2. `webapp/protype-2/src/App.tsx` — chat sidebar rendering (message loop around line ~867)
3. `webapp/protype-2/src/xano.ts` — `AiMessageResponse` type (has `progress` and `cell_updates` fields)
4. `webapp/protype-2/src/types.ts` — `Message` type

**What to change:**
1. **2.02:** In `App.tsx` message render loop, after each AI message bubble, conditionally render a chip when `cell_updates.length > 0` showing `"{n} cells updated · {progress.percentage}%"` in muted zinc-400, text-[10px] styling
2. **2.09:** Write/run workflow tests for Phase 2 stories + Playwright tests for chip rendering + full end-to-end simulation regression

**QA after implementation:**
- Playwright: verify chip appears after AI writes cells, does not appear for chat-only replies
- Full regression: all Epic 1 tests pass, all Phase 2 workflow tests pass, 5-10 simulation scenarios pass with domain-aware probing

---

## Scalable AI Agent Epic 2 — Response Quality, Domain Awareness & Interview Intelligence

### Purpose

Upgrade the AI agent from a **mechanically correct** tool-caller to a **domain-aware interview facilitator** that produces concise replies, understands what each lens means, and refuses to write garbage data into cells.

### Problem

The agent (Epic 1) works end-to-end — tools fire, cells update, structure mutates. But the **experience is unrefined**:

1. **Responses are too long** (~170 words). The reply bundles confirmation + stats + question into a wall of text. In the 384px sidebar, the actual question gets pushed below the fold. Research shows messages over 90 words see a 48% drop in read-through rate.
2. **The agent is domain-ignorant.** It sees lens labels ("Cascade Risk", "Escalation Trigger") but has zero understanding of what they mean. It can't ask domain-specific probing questions or recognize when an answer belongs in a different lens.
3. **No quality gate.** The agent writes whatever it extracts — even one-word vague answers like "confusion" or "slow". This inflates progress % with useless data that isn't actionable.

### Evidence

10 user simulations (delivery driver, SaaS PM, healthcare ops, vague answerer, info dumper, corrector, mode switcher, returning user, non-technical user, power user) revealed:

- **Response too long:** 8/10 simulations
- **Missing lens definitions:** 10/10 simulations
- **No quality gate:** 7/10 simulations

### Solution

Three changes, sequenced for zero-downtime delivery:

1. **Prompt rewrite** — Shorten output format rules, ban inline stats, enforce <60 word replies
2. **Lens semantic layer** — Add `description` field to `journey_lens`, populate defaults, inject into dynamic context
3. **Quality gate** — Add answer evaluation rules to system prompt with per-lens minimum thresholds

### Scope

- Rewrite the agent system prompt (output format + quality gate sections)
- Add `description` field to `journey_lens` table schema
- Populate lens descriptions in `create_draft` scaffold
- Update orchestrator lens injection to include descriptions
- Add frontend progress chip component (replaces inline stats text)
- Add interview probing strategies to system prompt

### Explicit non-goals

- Structured output rendering (accept/reject cards) — deferred to Epic 3
- Undo/versioning — deferred to Epic 3
- Conversation summarization / token windowing — deferred to Epic 3
- Bulk status operations (batch confirm/lock) — deferred to Epic 3
- Export / share functionality

---

### Epic 2A: Concise AI Responses (<60 Words)

**US-AI-2.01 — Rewrite system prompt output format for brevity**
- **Story:** As a user, I want the AI's replies to be short and conversational so that the question I need to answer is always visible without scrolling.
- **Acceptance Criteria:**
  - Output format section of system prompt enforces a 60-word maximum on visible replies.
  - Prompt explicitly bans listing out cell writes in the reply text.
  - Prompt bans including progress percentages in the reply text.
  - Prompt includes a good/bad example demonstrating the expected format.
  - Agent reply after writing cells is: one short confirmation sentence + the next question.
- **Changes:** `agents/2_journey_map_assistant.xs` — replace Output format section.

**US-AI-2.02 — Add frontend progress chip below AI messages**
- **Story:** As a user, I want to see a small badge showing "3 cells updated · 39%" below each AI message so I get progress info visually without the AI saying it in text.
- **Acceptance Criteria:**
  - When `cell_updates.length > 0`, render a small chip below the AI message bubble.
  - Chip shows: `{n} cells updated · {progress.percentage}%` in muted styling.
  - Chip is non-interactive, visually subtle (zinc-400, text-[10px]).
  - If no cells were updated, no chip is rendered.
  - Progress percentage comes from the API `progress` field, not from AI text.
- **Changes:** `webapp/protype-2/src/App.tsx` — add chip component in message render loop.

---

### Epic 2B: Lens Semantic Layer (Domain Awareness)

**US-AI-2.03 — Add `description` field to `journey_lens` table**
- **Story:** As the system, I need each lens to carry a semantic definition so the AI agent understands what "Cascade Risk" or "Key Variable" actually means.
- **Acceptance Criteria:**
  - `journey_lens` table gains: `text description? filters=trim`.
  - Existing lenses with no description continue to work (nullable).
  - Field is readable via all existing lens GET endpoints.
  - Field is writable via lens POST/PUT endpoints.
- **Changes:** `tables/8_journey_lens.xs` — add `description` field.

**US-AI-2.04 — Populate default lens descriptions in `create_draft`**
- **Story:** As a user creating a new journey map, I want the default 10 lenses pre-loaded with definitions so the AI immediately knows what each lens means.
- **Acceptance Criteria:**
  - Each of the 10 default lens seeds in `create_draft` includes a `description`.
  - Definitions:
    - `description`: "Brief summary of what happens at this stage — the core activity."
    - `customer`: "Who is the end customer at this stage? What do they experience or feel?"
    - `owner`: "The single team or role responsible for this stage succeeding."
    - `supporting`: "Other teams/roles that contribute but don't own the outcome."
    - `painpoint`: "The #1 friction or frustration. Must be specific — include frequency or impact."
    - `variable`: "The single critical factor determining success or failure. Must be measurable."
    - `risk`: "When this stage fails, which downstream stages break? Describe the domino chain."
    - `trigger`: "The threshold or event requiring escalation. Must include a measurable condition."
    - `notifications`: "What notifications fire, to whom, via what channel? Format: [Channel]: [Recipient] — [Content]."
    - `systems`: "The specific technology, software, or tools involved. Be specific, not generic."
  - Existing maps are NOT backfilled (non-breaking). New maps get descriptions automatically.
- **Changes:** `apis/journey_map/42_journey_map_create_draft_POST.xs` — add `description` to each lens seed.


**US-AI-2.05 — Inject lens descriptions into orchestrator dynamic context**
- **Story:** As the AI agent, I need lens definitions in my system prompt so I can ask domain-specific questions and recognize which lens an answer belongs to.
- **Acceptance Criteria:**
  - Orchestrator lens injection changes from `"Top Pain Point (painpoint)"` to `"- **Top Pain Point** (painpoint): The #1 friction or frustration. Must be specific..."`.
  - Each lens with a non-null `description` is rendered as a bullet with label, key, and definition.
  - Lenses with null descriptions fall back to label + key only (backward compatible).
  - Dynamic context is assembled fresh every call — never cached.
- **Changes:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs` — update the `foreach ($lenses)` block.

**US-AI-2.06 — Add interview probing strategies to system prompt**
- **Story:** As the AI agent, I need lens-specific probing question patterns so I know how to dig deeper for each type of data — not just generic "tell me more."
- **Acceptance Criteria:**
  - System prompt includes a new section: "Interview probing strategies per lens type."
  - Each of the 10 default lenses has a targeted question pattern:
    - Description: "Walk me through what happens step by step."
    - Customer: "What does the customer see, feel, or do at this point?"
    - Owner: "Who is THE one person/team accountable if this stage fails?"
    - Supporting: "Who else is involved? What's their specific contribution?"
    - Pain Point: "What's the biggest frustration? How often? What's the impact?"
    - Key Variable: "If you could only measure ONE thing, what predicts success?"
    - Cascade Risk: "When this breaks, what downstream stages fall apart?"
    - Escalation Trigger: "At what point does someone need to step in? What's the threshold?"
    - Notifications: "What notifications fire? Who gets them, through what channel?"
    - Systems: "What specific software, hardware, or tools are used here?"
  - Probing questions are used as fallbacks when the user's answer is too vague.
- **Changes:** `agents/2_journey_map_assistant.xs` — add new section after Interview mode rules.

---

### Epic 2C: Answer Quality Gate

**US-AI-2.07 — Add quality evaluation rules to system prompt**
- **Story:** As a user, I want the AI to probe deeper on vague answers instead of writing useless data like "confusion" into my cells so that every filled cell contains actionable, specific content.
- **Acceptance Criteria:**
  - System prompt includes a new section: "Answer quality gate (Interview mode only)."
  - Gate defines minimum quality thresholds per lens type:
    - Pain Point: must include WHAT + WHO/HOW OFTEN.
    - Key Variable: must be measurable, not a vague noun.
    - Cascade Risk: must reference at least 2 stages.
    - Escalation Trigger: must include a threshold or condition.
    - Notifications: must include channel + recipient + content.
    - Description/Customer/Owner/Supporting/Systems: at least one specific detail.
  - When an answer is too vague, AI does NOT write the cell. Instead it:
    1. Acknowledges what the user said
    2. Probes deeper with a specific follow-up
    3. Only writes once it has a specific, actionable answer
  - Exception: if user says "just write it" or "that's all I have", write as-is.
- **Changes:** `agents/2_journey_map_assistant.xs` — add new section before Output format.

**US-AI-2.08 — Backfill lens descriptions for existing maps**
- **Story:** As an existing user with maps created before Epic 2B, I want a one-time migration that populates default descriptions on my existing lenses so the AI agent becomes domain-aware on my old maps too.
- **Acceptance Criteria:**
  - A utility endpoint or function: `POST /journey_lens/backfill_descriptions`.
  - For each lens where `description IS NULL` and `key` matches a known default key, populate the default description.
  - Custom lenses (non-default keys) are skipped.
  - Endpoint is idempotent — running it twice has no effect.
  - Returns count of lenses updated.
- **Changes:** New endpoint in `apis/journey_map/` or a one-time function.

**US-AI-2.09 — Validation and smoke testing for Epic 2**
- **Story:** As the team, we want automated tests confirming: (a) lens descriptions are stored and injected, (b) the quality gate rejects vague answers, (c) AI responses stay under 60 words.
- **Acceptance Criteria:**
  - Workflow test: `create_draft` → verify all 10 lenses have non-null descriptions.
  - Workflow test: load_bundle → verify lens descriptions appear in response.
  - Playwright test: send a vague one-word answer → verify AI probes deeper (doesn't immediately write cell).
  - Playwright test: send a detailed answer → verify AI writes cell AND reply is under 80 words.
  - Playwright test: verify progress chip renders below AI message when cells are updated.
  - All existing Epic 1 tests continue to pass.
- **Changes:** New workflow test file + Playwright test additions.

---

### Recommended build order

```
US-AI-2.01 → US-AI-2.07 → US-AI-2.03 → US-AI-2.04 → US-AI-2.05 → US-AI-2.06 → US-AI-2.08 → US-AI-2.02 → US-AI-2.09
```

**Phase 1 — Prompt-only (zero schema changes, deploy immediately):**
`US-AI-2.01` (shorten replies) → `US-AI-2.07` (quality gate)

**Phase 2 — Schema + orchestrator:**
`US-AI-2.03` (add description field) → `US-AI-2.04` (populate defaults) → `US-AI-2.05` (inject into context) → `US-AI-2.06` (probing strategies)

**Phase 3 — Migration + frontend + tests:**
`US-AI-2.08` (backfill existing maps) → `US-AI-2.02` (progress chip) → `US-AI-2.09` (validation)

### Architecture delta from Epic 1

```
Epic 1:  Lens label → Agent sees "Cascade Risk (risk)" → Generic question
Epic 2:  Lens label + description → Agent sees "Cascade Risk (risk): When this stage
         fails, which downstream stages break?" → Domain-aware probe → Quality gate
         → Only writes specific, actionable content

Frontend:  AI text reply (170 words) → AI text reply (<60 words) + progress chip
```

### Success metrics

| Metric                                   | Before (Epic 1) | Target (Epic 2) |
|------------------------------------------|------------------|------------------|
| Avg AI response word count               | ~170             | < 60             |
| Cells with < 10 words (garbage)          | ~40%             | < 10%            |
| Cascade Risk cells referencing 2+ stages | ~10%             | > 70%            |
| Escalation Trigger cells with thresholds | ~15%             | > 80%            |
| Avg turns to fill a cell                 | 1.0              | 1.5–2.0          |
