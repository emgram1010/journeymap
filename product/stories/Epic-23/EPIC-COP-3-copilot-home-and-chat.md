# EPIC-COP-3 — Copilot home and chat: its own maps, one business at a time, one place to talk

**Status:** 📋 Not started. Written 2026-11-14 (Fable 5.2).
**Model:** **Sonnet 5.5.** Opus 5.5 (or Fable 5.2) review of story 02's "one business only" rule.
**Depends on:** COP-1 (identity, scope). Can run in parallel with COP-2.
**Risk:** medium. Mostly screens on storage that already exists.

---

## 1. Goal

**Pain:** "How will I talk to this AI agent?" Today's chat sits inside one map and only edits that
map. There is nowhere to say "I want this business at $2M in 3 years".

**Fix:** one copilot chat per business, reachable from every screen. The copilot keeps its own
"how I work" maps, separate from what it knows about each business.

**Win:** one conversation that covers the whole business — maps, plans and work — and never mixes
two businesses.

---

## 2. Design

```
┌ Any screen (maps · planner · approvals · reports) ─────────┐┌ Copilot ─────────────────────┐
│                                                            ││ Business: [ Business A  ▾ ]  │
│  (the page you were on stays visible)                      ││ ──────────────────────────── │
│                                                            ││ You: I want …                │
│                                                            ││ Copilot: Here is what I'd    │
│                                                            ││  need to know first …        │
│                                                            ││  ▸ 2 items waiting for you   │
└────────────────────────────────────────────────────────────┘└──────────────────────────────┘

The copilot's own architecture ("how I work")          A business's architecture
  how to research · how to build maps                    what it knows and does for that business
  how to learn · how to ask for approval                 (strategy, processes, exceptions)
        shared by every business in the account                never shared
```

- **One chat per business, not per map.** The existing map chat stays as it is, for editing one map.
- **The business is always on screen.** Switching it starts a different conversation; nothing
  carries over.
- **The copilot's own maps are its operating manual.** An AI actor row can already point at one
  (`agent_map_id`); this epic gives the copilot a home for them.

---

## 3. Stories

### US-COP-3-01 — The copilot's own "how I work" architecture
**Status:** 📋 Not started.

**As an** owner, **I want** the copilot's working methods written down as maps I can read,
**so that** I can see and improve how it works.

```gherkin
Scenario: A new copilot comes with a starter set
  When a copilot is created for my account
  Then it has its own architecture with starter maps:
    how to research, how to build maps, how to learn, how to ask for approval

Scenario: I can read and edit them
  When I open the copilot's architecture
  Then its maps open like any other map, clearly labelled "Copilot's own"

Scenario: Its methods apply to every business
  Given two businesses in my account
  Then the copilot follows the same "how I work" maps in both

Scenario: The copilot proposes changes to its own methods; it does not make them
  When it wants to change a "how I work" map
  Then it creates a draft for me to publish
```

**Build notes.** Decision D-2: one copy per account, made from a starter template; no cross-account
read. Mark the architecture as the copilot's own in a side table (no new column on
`journey_architecture` — it has text validators). The starter maps' content is written with the
founder, not invented in code.

### US-COP-3-02 — One business at a time
**Status:** 📋 Not started. **Opus review.**

**As an** owner, **I want** each copilot conversation tied to one business,
**so that** what it learns about one never shows up in another.

```gherkin
Scenario: The conversation names its business
  When I open the copilot
  Then the business it is working on is shown at the top

Scenario: Switching business switches conversation
  When I pick another business
  Then I see that business's conversations, and none from the first

Scenario: It cannot reach across
  Given a conversation about business A
  When I ask about something in business B
  Then it says that belongs to another business and offers to switch

Scenario: New knowledge lands in the right place
  When it drafts a map during a conversation about business A
  Then the draft is created inside business A's architecture
```

**Build notes.** The session's business is the scope COP-1 story 03 enforces — this story is the
screen for it, and must add **no second copy** of the rule. `agent_conversation` already has
`journey_architecture_id`; confirm how today's per-map conversations use it before reusing it.

### US-COP-3-03 — One chat, reachable everywhere
**Status:** 📋 Not started.

**As an** owner, **I want** to open the copilot from any screen,
**so that** I can ask it something without leaving what I am doing.

```gherkin
Scenario Outline: The copilot opens from every area
  When I am on <screen> and open the copilot
  Then it opens beside the page, and the page stays visible
  Examples:
    | screen            |
    | a map             |
    | the planner       |
    | approvals         |
    | reports           |

Scenario: It picks up where we left off
  When I close and reopen it
  Then the same conversation is there

Scenario: The map chat still works
  When I open the chat inside a map
  Then it behaves exactly as it does today
```

**Build notes.** Side-panel pattern (same as the job panel, PUX-1). Reuse `agent_conversation` /
`agent_message`; no second chat store. Esc does not close it while a dialog is open on top
(PUX R-3). Not shown to people without the module grants the copilot itself needs.

### US-COP-3-04 — It knows what I am looking at
**Status:** 📋 Not started.

```gherkin
Scenario: "This" means the thing on screen
  Given I am looking at a job in the planner
  When I ask "why is this late?"
  Then it answers about that job

Scenario: It says when it cannot tell
  Given nothing specific is selected
  When I say "fix this"
  Then it asks me which thing I mean
```

### US-COP-3-05 — It asks, and it shows what is waiting
**Status:** 📋 Not started.

```gherkin
Scenario: One question at a time
  When it needs information to continue
  Then it asks one clear question and waits

Scenario: Waiting items are linked in the chat
  Given it created items that wait for me
  Then the chat shows how many, with a link to Approvals

Scenario: It reports plainly
  When it finishes a piece of work
  Then it says what it did, what it did not do, and what it needs from me
```

**Build notes.** Depends on COP-2 for the link; until then, show "needs your OK" inline.

### US-COP-3-06 — It can read the whole business
**Status:** 📋 Not started.

**As an** owner, **I want** the copilot to see the maps, plans and work record of its business,
**so that** its answers are about what is really there.

```gherkin
Scenario: It reads all three layers
  When I ask "what did we plan this week and what actually happened?"
  Then it answers from the plan and the work record of this business

Scenario: It says what it could not see
  Given it lacks the grant for one module
  Then it says that part is switched off for it, and does not guess
```

**Build notes.** Read tools only (COP-5 adds the write tools). Each read still passes COP-1's gate
and is logged.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | One side table marking an architecture as the copilot's own (unique per account). No change to `agent_conversation` unless a field is truly missing — check first |
| Delete behaviour | A copilot's own architecture cannot be deleted while the copilot exists |
| Validation | A conversation's business cannot be changed after it starts |
| Error codes | `E-COP-020` no copilot for this account · `E-COP-021` conversation belongs to another business. Feature `COP-3` |
| Events | Conversation started; business switched; a turn that failed (with the reason) |

## 5. Counter-measures

| Risk | Counter-measure |
|---|---|
| The existing map chat changes behaviour | It is not touched; a before/after replay proves it |
| Old conversations appear under the wrong business | Only conversations created by the copilot chat are listed in it |
| The panel hides page controls on narrow screens | Full-width on narrow screens, like the job panel |
| The copilot "remembers" across businesses through its own maps | Its own maps hold methods only; a test asserts business facts are written to the business architecture |

## 6. Test plan

| ID | Kind | What |
|---|---|---|
| UT-COP-3-01 | Unit | Conversation list filtered by business; context summary of the current screen |
| FT-COP-3-01 | HTTP | Starter architecture created once per account; second attempt refused |
| FT-COP-3-02 | HTTP | A draft made in a business-A conversation lands in business A |
| UI-COP-3-01 | Browser | Open from map, planner, approvals, reports; reopen keeps the conversation |
| UI-COP-3-02 | Browser | Switch business; nothing carries over |
| REG | Suites | `npm test`, `tsc`, build; map chat replay identical |

## 7. Test results

Not run. Nothing is built.
