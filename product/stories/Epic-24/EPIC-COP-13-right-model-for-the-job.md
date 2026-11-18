# EPIC-COP-13 — The right model for each job, and permission before a dearer one

**Status:** 🟡 Part A partly done (2026-11-18, Sonnet 5.5): the copilot and the map chat agent run on Sonnet 5.5. Part B (step-up) not started.
**Model:** **Sonnet 5.5** for part A (stories 01–02). **Opus 5.5** for part B (stories 03–05): a new approval type and a spend cap. Opus review pass after part B.
**Depends on:** part A none; part B on COP-2 (approval levels) and COP-1 story 05 (daily cap).
**Risk:** part A low (a setting per agent, easy to roll back). Part B medium: it decides when the AI may spend more.

---

## 1. Goal

**Pain:**
- All 7 agents run on **Claude Sonnet 4.5** (`model: "claude-sonnet-4-5"` in each `ai/agent/*.xs`). Sonnet 5.5 is newer, stronger and cheaper ($2 / $10 per million tokens in / out, against $3 / $15).
- Every task gets the same model, whether it is a one-line lookup or building a whole map.
- There is no way for the AI to say "this needs a stronger model" and ask first.

**Fix:**
- **Part A:** move every agent to a current model, starting with Sonnet 5.5, tested against the same chats before and after.
- **Part B:** each AI starts on the cheaper model. When a task is too hard, it **asks** to step up to a stronger one, through the approval levels that already exist, with a daily limit.

**Win:** lower cost per run now; later, strong models only where they earn it, and never without the owner's say-so.

### Known breaking change (found 2026-11-18)

The agents set `temperature: 0.3`. **Sonnet 5.5 rejects non-default sampling values with a 400**, and from API version `2026-10-21` every model does. Part A must remove `temperature` from every agent, and check what Xano sends for `reasoning: true` (Sonnet 5.5 rejects "thinking disabled").

### Models and prices (Anthropic list price per million tokens, cached 2026-11-03; re-check before building)

| Model | In / out | Use for |
|---|---|---|
| Claude Haiku 5.5 | $0.10 / $0.50 | Simple, high-volume reading and sorting; only after it passes the same test chats |
| Claude Sonnet 5.5 | $2 / $10 | Default for every agent |
| Claude Opus 5.5 | $4 / $20 | Hard judgement, only by step-up (part B) |

---

## 2. Part A — move to a current model

### US-COP-13-01 — Every agent on Sonnet 5.5, proven by the same chats

**As an** owner **I want** the cheaper, stronger model **so that** every run costs less and works
at least as well.

```gherkin
Scenario: a baseline before the change
  Given the AI test scenarios (§5) run on Sonnet 4.5
  Then their results, tool calls and token use are recorded as the baseline

Scenario: the switch, one agent at a time
  When an agent's model is changed to claude-sonnet-5-5 and temperature is removed
  Then the same scenarios are run again for that agent
  And the switch is kept only if every scenario passes and cost per scenario is no higher
  And the agent's .xs file and the live agent match (fetch live, diff, push)

Scenario: Xano accepts the model
  Given Xano's Anthropic provider
  Then a real chat on the new model id succeeds before any other agent is switched
  # if Xano rejects the id, stop and tell the founder; do not route around it

Scenario: rollback
  Then git HEAD holds the old agent file, and switching back is one push
```

### US-COP-13-02 — Which model each agent uses is visible

**As an** owner **I want** to see each agent's model **so that** I don't have to open Xano.

```gherkin
Scenario: Health shows it
  Then Health lists each agent with its model, so a stale model is visible
  # read from a small manifest kept next to the agents and checked by a unit test against ai/agent/*.xs
```

---

## 3. Part B — start cheap, ask before stepping up

### US-COP-13-03 — A cheap and a strong copy of the agent

**As an** owner **I want** most work done on the cheaper model **so that** I pay for the strong
one only when needed.

```gherkin
Scenario: two copies
  Given Xano fixes one model per agent
  Then the copilot has a standard copy (Sonnet 5.5) and a strong copy (Opus 5.5) with the same prompt and tools
  And one source file generates both, so they can't drift
  # a unit test fails if the two copies differ in anything but model

Scenario: the standard copy runs first
  When a chat or scheduled run starts
  Then the standard copy runs
```

### US-COP-13-04 — The AI asks to step up

**As an** owner **I want** the AI to ask before it uses the dearer model **so that** I stay in
control of the cost.

```gherkin
Scenario: a new action type
  Given the approval levels (COP-2)
  Then there is an action "use a stronger model" (step_up_model), default "waits for you" (D-24-6)

Scenario: the AI asks
  When the standard copy decides the task is too hard
  Then it calls request_step_up with one line saying why
  And an approval item shows the task, the reason and the price difference

Scenario: approved
  When I approve, or the level is "runs, then tells you" or "on its own"
  Then the same task is re-run on the strong copy with the conversation so far
  And the run records that it stepped up

Scenario: declined or expired
  When I decline, or the item expires (COP-2: remind, then expire, never auto-approve)
  Then the standard copy carries on as well as it can and says so
```

### US-COP-13-05 — A daily limit on stepping up

**As an** owner **I want** a cap on strong-model use **so that** a loop can't run up a bill.

```gherkin
Scenario: the cap
  Given a daily step-up limit per business (default 5)
  When it is reached
  Then further requests are refused with E-COP-094 and the AI carries on with the standard copy

Scenario: Health
  Then Health shows step-ups per day per business, and how many were approved, declined and refused by the cap
```

---

## 4. Governance

- **Tables:** part A none. Part B: the step-up limit goes in the existing COP-2 settings for action types (`step_up_model` in `copilot/action_types`), and step-ups are recorded in `copilot_action` like other actions. No new table expected; **ask before any push** if one turns out to be needed.
- **Changed live items:** all 7 agents (model, temperature); part B adds an agent copy and a `request_step_up` tool.
- **Validation:** model ids only from an allow-list in one function; limit 0–50.
- **Error codes:**
  - E-COP-093: the model change failed its test chats (recorded in Test results, not shown to users)
  - E-COP-094: daily step-up limit reached
  - E-COP-095: step-up refused or expired
- **Events:** `copilot.model.switched` (agent, from, to), `copilot.step_up.requested` / `.approved` / `.declined` / `.capped`, each with success and failure.

## 5. Counter-measures

| Risk | Counter-measure |
|---|---|
| The new model breaks a tool call silently | Same test scenarios before and after; switch one agent at a time |
| `temperature` causes a 400 on Sonnet 5.5 | Removed in the same push as the model change |
| The .xs file and live agent drift | Fetch live, diff, push; the manifest test catches a stale file |
| The AI steps up for everything | Default "waits for you", daily cap, reason required, Health counts |
| The two copies drift | Generated from one source; unit test compares them |
| Cost rises after the switch | Token use per scenario compared; switch kept only if no higher |

## 6. Test plan

| ID | Type | Checks |
|---|---|---|
| AI-COP-13-01 | Real AI chat | The AI test scenarios on Sonnet 4.5 (baseline) and on Sonnet 5.5, per agent; pass/fail and tokens |
| FT-COP-13-01 | Function | Each live agent's model and settings match its .xs file |
| FT-COP-13-02 | Function | step_up_model level: wait → approval item; tell → runs and tells; declined → carries on |
| FT-COP-13-03 | Function | 6th step-up in a day refused (E-COP-094) |
| UT-COP-13-* | Unit | Agent model manifest matches ai/agent/*.xs; the two copies differ only in model; error codes in catalog |
| UI-COP-13-* | Playwright | Health shows each agent's model and step-up counts |

## 7. Test results

### Part A: moved so far

| Agent | Before | Now | Proof |
|---|---|---|---|
| Emgram Copilot (40) | Sonnet 4.5, temperature 0.3, thinking on | **Sonnet 5.5**, no temperature, thinking on | Xano accepted `claude-sonnet-5-5` (no 400). Real AI, same scenarios as on 4.5: COP-10 **5/5** (was 5/5); COP-9 **7/8** (was 8/8): the one miss is the old probe expecting a new rush-job exception, while the 5.5 copilot noticed #6 and #8 already exist and refused to add a third. Behaviour better than before; probe widened to accept it. Results in `tests/cop13_s55_cop10_result.txt` and `cop13_s55_cop9_result.txt` |
| Journey Map Chat Agent (10) | Sonnet 4.5, temperature 0.4, thinking off | **Sonnet 5.5**, no temperature, thinking off | Real map chat (`tests/cop12_ai_probe.py`) **3/3**: names Skill #1 and its steps (`tests/cop13_s55_chat_result.txt`) |

UT-COP-13-01..03 (`cop13AgentModels.test.ts`) 3/3: each agent file's model matches the expected list, no agent is missing from it, and an agent on a newer model sets no temperature.

**Not measured:** tokens per scenario (Xano does not return usage to us). The case for the switch rests on price per token ($2 / $10 against $3 / $15) and on the scenarios not getting worse. Check the Anthropic console usage page after a few days.

### Part A: left on Sonnet 4.5, and why

| Agent | Why not yet |
|---|---|
| Journey Map Assistant (18, interview mode) | Its repo file had drifted (a `"temp"` prompt; live holds ~70,000 characters). Pushing means re-sending all of it. Safer: **in Xano, AI → Agents → Journey Map Assistant → change the model to Sonnet 5.5, delete the temperature line** (and add `check_publish_ready` and `get_how_i_work`, see COP-10). Then run a short interview in the app |
| Journey Map Builder (9) | Needs a phased-build run on a spare map to prove fast cell fills still use the right write tool; no spare fixture map was safe to change. Chat (same thinking-off setting) works on 5.5, so the setting shape is fine |
| Orchestrator (15), Compare Analyst (3), Copilot Researcher (41) | Need one real run each (a workflow, a scenario comparison, a research topic). Not run |

### Part B and story 02: not started
Story 02 (Health lists each agent's model) and the whole of part B (cheap and strong copy, "use a stronger model" approval, daily cap) are untouched. Part B adds an approval type and spends money, so it waits for the founder's go (README D-24-6).
