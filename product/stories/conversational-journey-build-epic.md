# Epic — Conversational Journey Map Build (CJB)

**Epic goal:** Transform the AI from a silent background builder into an active PM collaborator —
one that reads the current map state before touching anything, asks the two or three questions
that actually matter, builds incrementally with visible progress, and flags what it was
uncertain about when it is done.

---

## Why This Exists

### The PM lens
A great PM never opens a blank doc and starts typing. They first look at what already exists,
identify what's missing or contradictory, ask the smallest set of questions that unlocks the
most information, and then draft — showing work as they go. The AI should operate the same way.

Today the agent skips all of that. It receives a "build me a map" message and immediately fires
8 sequential phases in silence. The user stares at a spinner for several minutes and then
receives a completed map with no explanation of the choices made. There is no conversation,
no sense of ownership, and no trust in the output.

### The UX lens
In a professional journey mapping workshop a facilitator does three things before a single
sticky note goes on the wall: (1) reviews any existing artifacts, (2) frames the scope clearly,
and (3) gets the room aligned on who the primary actor is. These are not bureaucratic steps —
they are the difference between a map that the team actually uses and one that gets filed away.

The AI's build flow should mirror this: orient, frame, align, then build with the team watching.

### The novice customer lens
A first-time user opening the product and typing "build me a pizza delivery journey map" has
no idea what stages or lenses are. They do not know what journey settings are. They cannot
evaluate a completed grid of 72 cells. What they can do is answer plain-language questions and
react to something concrete that just appeared on screen. The AI must meet them there — no
jargon, no wall of text, something visible within 30 seconds.

---

## The Five Conversation Phases

### Phase 0 — Silent Pre-Check (~3 sec, no user interaction)
Before the AI says anything, it reads the map state and classifies what it finds.

| Map state | Classification |
|---|---|
| No stages, no settings | `fresh` |
| Settings filled, no cells | `ready_to_build` |
| Cells partially filled (< 70%) | `in_progress` |
| Cells mostly filled (>= 70%) | `near_complete` |
| Contradictions detected between cells | `has_quality_flags` |

The classification determines the opening message in Phase 1.

**What the AI reads silently:**
- `get_map_state` — stage count, lens count, cell fill rate by lens
- `journey_settings` — which of the 11 fields are populated
- Cell content spot-check — description vs customer lens for the same stage (contradiction scan)

---

### Phase 1 — Contextual Opening (1 AI message, ≤ 50 words)
The AI's first message is determined by the classification above — never a generic greeting.

**`fresh` map:**
> "Let's map this out. What process or experience are we building? Give me a quick description
> and I'll have a structure ready in under a minute."

**`ready_to_build` map (settings filled, no cells):**
> "I can see you've set up a map for [title] — [N] stages, [actor] as the primary actor.
> Ready to build? I'll fill it in and check in once along the way."

**`in_progress` map:**
> "You're about [N]% done. [Lens A] and [Lens B] are mostly filled.
> [Lens C] and [Lens D] are empty. Want me to pick up from there?"

**`has_quality_flags` map:**
> "Before I continue — I spotted something worth checking: [stage] Description says '[X]'
> but the Customer row says '[Y]'. Want to resolve that first, or should I keep going?"

---

### Phase 2 — Targeted Discovery (max 3 questions, only if gaps exist)
The AI only asks questions that are missing from `journey_settings` AND are load-bearing for
the build. Questions are asked one at a time, not as a list.

**Priority order:**

1. **Primary actor** (if null) — asked first, blocks scaffold
   > "Who are we following through this map — the customer placing the order, the delivery
   > driver, or both?"

2. **Scope / start + end point** (if null) — asked second
   > "Where does this journey start and end for them? Like, does it begin when they open the
   > app, or when they first feel hungry?"

3. **One domain insight** (optional, only if context is thin) — asked last
   > "Any known pain points or moments that matter most? Even a rough sense helps me prioritise."

If all three are already in `journey_settings` → skip Phase 2 entirely and go straight to build.

---

### Phase 3 — Build with Live Narration
The AI builds phase by phase and sends a short message after each one. Each message:
- Confirms what was just done (one sentence)
- Shows a quick stat (N cells filled)
- Asks ONE targeted question about something it had to assume

**Narration sequence:**

| Build phase | AI message after completion |
|---|---|
| Scaffold | "Structure ready — [N] stages, [N] lens rows. Filling in the process descriptions now..." |
| Identity | "Actors named. Starting on the customer experience..." |
| Description | "Process steps done. Quick check: at [Stage X], is it [assumption]? I can adjust if not." |
| Customer | "Customer experience mapped. I treated [pain point] as the main friction — does that land?" |
| Internal | "Internal operations filled. Building pain points and structural analysis..." |
| Structural + Metrics | "Pain points, systems, and metrics done." |
| Verify | "All done — [N]/[N] cells filled." |

---

### Phase 4 — Confidence Report (1 AI message, always shown)
After every build, the AI surfaces exactly 3 things it was least certain about.
These are not apologies — they are PM handoffs.

Format:
> "Three things I made calls on — worth a quick review:
> 1. **[Stage] metrics** — I estimated [X]% completion rate. Update if you have real data.
> 2. **[Stage] structure** — I added a '[Stage name]' step you didn't mention. Felt necessary.
> 3. **[Cell A] and [Cell B]** — these overlap. Might be worth merging."

---

### Phase 5 — Refinement Invitation (1 AI message)
The AI does not just stop. It offers three specific entry points for what to do next.

> "What would you like to refine?
> → 'Walk me through [stage]' — I'll narrate what I wrote and you can correct it
> → 'Update [thing]' — tell me what changed and I'll fix it
> → 'Flag what looks off' — I'll highlight the cells I'm least confident about first"

---

## User Stories

### US-CJB-01 — Silent pre-check on build request
**Story:** As a user who sends a build request, I want the AI to read the current map state
before responding so that its first message is relevant to where I actually am, not a generic
greeting.

**Acceptance criteria:**
- On any message containing a build intent, the agent calls `get_map_state` and reads
  `journey_settings` before generating its opening reply.
- The agent classifies the map as `fresh`, `ready_to_build`, `in_progress`, `near_complete`,
  or `has_quality_flags` based on fill rate and setting completeness.
- The opening message matches the classification — no generic "Let's get started!" for a
  map that is already 60% filled.
- Pre-check adds no more than 3 seconds of perceived latency (tool call is fast).

---

### US-CJB-02 — Contextual opening message
**Story:** As a user, I want the AI's first message to reflect the actual state of my map so
that I immediately understand what it found and what it plans to do.

**Acceptance criteria:**
- `fresh` → AI asks what the map is about (one open question).
- `ready_to_build` → AI confirms settings it can see and asks for build confirmation.
- `in_progress` → AI summarises what's filled and what is empty, offers to continue.
- `near_complete` → AI summarises completion and offers targeted refinement.
- `has_quality_flags` → AI surfaces the specific contradiction(s) before proceeding.
- Opening message is ≤ 50 words.

---

### US-CJB-03 — Data quality scan
**Story:** As a user with a partially filled map, I want the AI to surface contradictions or
stale data before building over it so that the completed map is internally consistent.

**Acceptance criteria:**
- Agent compares description lens content against customer lens content for the same stage.
- Agent flags when a stage label is still a default placeholder (e.g. "Stage 1", "New Stage").
- Agent flags when a `journey_settings` field conflicts with cell content
  (e.g. `primary_actor = "driver"` but customer lens is filled with customer-facing content).
- Flags are surfaced as plain-language observations, not error codes.
- User can respond "keep going" to proceed past flags without resolving them.

---

### US-CJB-04 — Targeted discovery intake (max 3 questions)
**Story:** As a user starting a build, I want the AI to ask only the questions that are
actually missing and load-bearing so that I'm not filling out a form before anything happens.

**Acceptance criteria:**
- Agent identifies which of the three priority fields are null in `journey_settings`:
  `primary_actor`, `start_point` / `end_point`, domain context.
- Questions are asked one at a time, not as a numbered list.
- If all three priority fields are already populated → Phase 2 is skipped entirely.
- User answers are written to `journey_settings` via `update_journey_settings` before scaffold.
- Max 3 exchanges before the build starts regardless of what is still missing.

---

### US-CJB-05 — Progressive build narration
**Story:** As a user waiting for the map to build, I want a brief AI message after each phase
so that I can see progress and know the AI is working, not frozen.

**Acceptance criteria:**
- After each build phase completes, the agent sends a message ≤ 30 words confirming what
  was done and how many cells were written.
- Each phase message includes ONE question about an assumption the agent made.
- The question is targeted — it refers to a specific stage, cell, or decision, not a generic
  "does this look right?"
- User can answer the question to refine that cell inline, or say "keep going" to skip.
- Phase messages appear in the conversation thread as regular assistant messages.

---

### US-CJB-06 — Post-build confidence report
**Story:** As a user reviewing a completed build, I want the AI to tell me specifically what
it was uncertain about so that I know where to focus my review time.

**Acceptance criteria:**
- After the final build phase, agent sends one message flagging exactly 3 low-confidence
  decisions.
- Flags are specific: stage + cell + what was assumed and why.
- Format is consistent: numbered list, ≤ 20 words per item.
- Flags do not rewrite cells — they surface information for the user to act on.
- If the build was < 30 cells (small map), flags list is reduced to 2 items.

---

### US-CJB-07 — Refinement invitation
**Story:** As a user who just received a completed build, I want the AI to offer me three
clear ways to continue so that I know how to refine the map without guessing at commands.

**Acceptance criteria:**
- After the confidence report, agent sends one message with three specific refinement offers.
- Offers reference actual content in the map (e.g. the stage with the lowest confidence,
  the lens with the most empty cells).
- User can pick any offer by replying naturally ("walk me through checkout", "update payment").
- Agent handles each offer type: stage walkthrough, cell update, confidence-ordered review.

---

### US-CJB-08 — Agent prompt: encode full CJB rules
**Story:** As the system, I want the agent's system prompt to include all CJB phase rules so
that the conversational build flow is consistent and repeatable across all maps.

**Acceptance criteria:**
- Agent prompt includes `## Pre-check rules` section (Phase 0 + Phase 1 logic).
- Agent prompt includes `## Discovery intake rules` section (Phase 2, max 3 Qs, priority order).
- Agent prompt includes `## Build narration rules` section (Phase 3, 30-word limit per message,
  one assumption question per phase).
- Agent prompt includes `## Confidence report rules` section (Phase 4, exactly 3 flags,
  specific format).
- Agent prompt includes `## Refinement invitation rules` section (Phase 5).
- All rules use the same "DO NOT" / positive instruction style as existing prompt sections.

---

### US-CJB-09 — Frontend: phase progress chips in chat thread
**Story:** As a user watching a build, I want to see progress indicators in the chat thread
after each phase so that the build feels alive and not like a black box.

**Acceptance criteria:**
- After each phase message from the agent, a small progress chip renders below the message:
  `[Phase name] · N cells · ✅ / ⚠️`.
- Chips reuse the existing `BuildSummaryPanel` data shape (already collected in `App.tsx`).
- Chips are collapsed by default; clicking expands the tool call detail (debug mode only).
- Progress chip does not render for the pre-check or discovery phases (no cells written there).
- Chips accumulate in the thread — user can scroll up and see the full build timeline.

---

## Build Time Target

| Scenario | Target elapsed time |
|---|---|
| Fresh map, user answers 2 questions | < 4 minutes total |
| Settings already filled, no questions needed | < 3 minutes total |
| In-progress map, picking up from 40% | < 2 minutes total |
| Near-complete map, refinement only | < 1 minute |

---

## Implementation Order

```
US-CJB-08 (agent prompt) →
US-CJB-01 + US-CJB-02 (pre-check + opening) →
US-CJB-03 (quality scan) →
US-CJB-04 (discovery intake) →
US-CJB-05 (narration) →
US-CJB-06 (confidence report) →
US-CJB-07 (refinement invitation) →
US-CJB-09 (frontend chips)
```

Prompt changes (US-CJB-08) ship first because every other story depends on agent behaviour.
Frontend chips (US-CJB-09) ship last because they depend on the narration contract being stable.

---

## Dependencies

- `ai-builder-reliability-observability-epic.md` — build loop must be stable before narration
  is layered on top.
- `agents/2_journey_map_assistant.xs` — all prompt changes land here.
- `apis/journey_map/81_journey_map_journey_map_id_build_full_POST.xs` — phase narration
  messages require the loop to emit per-phase assistant messages, not just a final result.
- `webapp/protype-2/src/App.tsx` — phase chips extend the existing `BuildSummaryPanel`.
