# EPIC-COP-13 — The right model for each job, and permission before a dearer one

**Status:** 🟡 Part A partly done (2026-11-18, Sonnet 5.5): the copilot and the map chat agent run on Sonnet 5.5. **Part B built and live (2026-11-19, Opus 5.5)** for the in-app copilot chat; story 02 (Health lists models) built 2026-11-19.
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
| Emgram Copilot Researcher (41) | Sonnet 4.5, temperature 0.2, thinking on | **Sonnet 5.5**, no temperature, thinking on | Real research turn through the copilot chat (`tests/cop13_researcher_probe.py`, real AI + web search, 86 s) **4/4**: drafted map 288 labelled `copilot_research` with sources and not tested; report names sources and what was general or thin. **No 4.5 baseline run** (it costs a real search and a real map); pass rests on the prompt's own promises. Search wording is not recorded by the tool log, so "no business details in searches" is not checked. File and live agree (canonical added to the file). Result in `tests/cop13_researcher_result.txt` |
| Journey Compare Analyst (3) | Sonnet 4.5, temperature 0.3, thinking on | **Sonnet 5.5**, no temperature, thinking on | Same real compare question on the same two maps before and after (`tests/cop13_compare_probe.py`): **5/6 before, 6/6 after**. The one before-miss is the optional closing question (the prompt says "optional"). Both used the real map titles, said "no data yet", declared no winner. The first after-run showed 5/6 only because my label check matched the words "each scenario are"; check fixed and rerun. **`get_stage_detail` was not exercised**: both maps have no scores, so the analyst had no reason to call it. Results in `tests/cop13_compare_before_result.txt` / `_after_result.txt` |
| Journey Map Builder (9) | Sonnet 4.5, temperature 0.3, thinking off | **Sonnet 5.5**, no temperature, thinking off; **prompt tidied** (leftover merge-conflict markers and the identical duplicate block they wrapped removed) | Real phased build on fresh fixture maps made through the MCP door (`tests/cop13_builder_probe.py`; description, customer and internal phases through `ai_message` `builder_mode`): **10/10 before, 10/10 after**. Each phase answered in one sentence; 11/11 cells filled in every row; description cells got text via the right tool and actor cells got actor fields with only allowed keys; structure unchanged. **Faster: 119 s total against 148 s.** Not covered: structural, metrics and identity phases; locked or confirmed cells; the scaffold phase (that runs on the Assistant). Fixture maps 289-293 are throwaways. Results in `tests/cop13_builder_before_result.txt` / `_after_result.txt` |
| Journey Map Chat Agent (10) | Sonnet 4.5, temperature 0.4, thinking off | **Sonnet 5.5**, no temperature, thinking off | Real map chat (`tests/cop12_ai_probe.py`) **3/3**: names Skill #1 and its steps (`tests/cop13_s55_chat_result.txt`) |

UT-COP-13-01..03 (`cop13AgentModels.test.ts`) 3/3: each agent file's model matches the expected list, no agent is missing from it, and an agent on a newer model sets no temperature.

**Not measured:** tokens per scenario (Xano does not return usage to us). The case for the switch rests on price per token ($2 / $10 against $3 / $15) and on the scenarios not getting worse. Check the Anthropic console usage page after a few days.

### Part A: left on Sonnet 4.5, and why

| Agent | Why not yet |
|---|---|
| Journey Map Assistant (18, interview mode) | Its repo file had drifted (a `"temp"` prompt; live holds ~70,000 characters). Pushing means re-sending all of it. Safer: **in Xano, AI → Agents → Journey Map Assistant → change the model to Sonnet 5.5, delete the temperature line** (and add `check_publish_ready` and `get_how_i_work`, see COP-10). Then run a short interview in the app |
| Orchestrator (15) | **Prompt corrupted** both live and in the repo (stray "â€”" text for dashes, arrows, box lines) | **Sonnet 5.5**, no temperature, thinking off, **prompt text repaired** (founder approved 2026-11-19; only characters changed, no wording) | **Weak proof, said plainly:** the only route that starts it is `POST journey_map/{id}/invoke`, and that returns `final_output: null` even when the run "completes" (it reads the wrong field of the agent's result). So the run is proven to **start and finish on 5.5 with no 400** (same as on 4.5: 4/6 both times, the two misses being the empty text), but **its behaviour was not observed**: no stage output, validation or subject question. Results in `tests/cop13_orch_before_result.txt` / `_after_result.txt` (`cop13_orch_probe.py`, map 260). **Update (founder approved, same day):** `invoke` now returns the agent's reply (it read a field that does not exist; now reads `result`, as the chat endpoints do; UT-COP-13-04). Rerun on 5.5: **6/6** and the text shows the agent answering sensibly, but it **cannot start a run: invoke never tells it the map id** (no Tool Logging block), so it asks for one and stops. That is an older defect: a map invoked this way (and agent delegation through `invoke_map`) has never actually executed. Also the agent **repeated its run ticket in its reply** (short-lived, test only; redacted in `cop13_orch_after2_result.txt`). **Both fixed the same day (founder approved):** `invoke` now sends the two blocks the agent's prompt expects ("Orchestrator Mode Active" and "Tool Logging" with the map id and a turn id) and an order never to repeat the ticket (UT-COP-13-05). Rerun (`cop13_orch_after3_result.txt`, map 260, real AI, 17 s) **8/8**: it ran the whole workflow on 5.5 for the first time: validated (no blockers), found no internal actor on any of the 4 stages, skipped them, reported 0 of 4 with a clear reason and what to set up, produced the completion artifact, offered the three exports and the one-time feedback offer; asked for nothing; no ticket in the reply. **No 4.5 baseline exists** because on 4.5 this route could not run a map at all. Not exercised: a map with an internal actor (real stage output), supporting actors, AI-agent delegation through `invoke_map`, resume. One oddity: it named the skipped stages although the prompt says not to surface them unless asked (fair here: the whole run was empty) |

### Part B: start cheap, ask before stepping up (2026-11-19, Opus 5.5)

**Built:**
- **Two copies, one source:** `Emgram Copilot` (agent 40, Sonnet 5.5) and `Emgram Copilot Strong` (agent 43, Opus 5.5). The strong copy is generated by `scripts/gen_strong_copilot.py`; it differs only in name, model, canonical and the missing `request_step_up` tool, so it cannot ask again. UT-COP-13-B-02 fails if they drift.
- **Approval type** `step_up_model` ("Use a stronger, dearer AI model for a hard task"): touches money, default **waits for you** (D-24-6), owner can change the level.
- **Tool** `request_step_up` (195): one-line reason required; **daily cap 5 per account per 24 h** checked BEFORE anything waits (E-COP-094); then the approval gate; when allowed it logs `copilot.step_up.granted` on the conversation.
- **Chat endpoint 643:** if a step-up was granted during this turn, the same messages are re-run on the strong copy and its answer replaces the first; `stepped_up` in the response; `copilot.step_up.ran` logged either way.
- Events: `copilot.step_up.requested` / `.capped` / `.granted` / `.ran`.

| Check | Result |
|---|---|
| Real AI (`tests/cop13b_ai_probe.py`, conversation 213) | **7/7**: everyday question stays on Sonnet; the copilot asked and item 47 waited, showing the reason and "about twice the price"; owner approved; the re-sent request re-ran the turn on Opus 5.5 (`stepped_up: true`, correct answer). Xano accepted `claude-opus-5-5` |
| Unit `cop13StepUp.test.ts` + model list | 7/7 + 3/3; full suite green |

**Cap as an owner setting (2026-11-19, founder approved the column):**
- New column `copilot_library_setting.step_up_daily_cap` (table 166; additive; 0 / no row = default 5). It lives with the other copilot limits, not in `action_types` (that catalogue is code, not per-account data).
- Saved by `POST copilot/library_settings` (668, admin, person only), bounds **1–20**, optional (0 = keep saved). Read by `GET copilot/skill_meta` (667) and by `request_step_up` (195).
- Screen: How I work → Limits → "Stronger-model uses per day", checked on the screen first (typing kept), server checks again.

| Check | Result |
|---|---|
| Real AI cap (`tests/cop13b_cap_probe.py`) | **8/8** (one rerun after a network drop): 21 refused; omitted cap kept; cap 1 saved and read back; the real copilot asked and was refused with E-COP-094, `stepped_up: false`, nothing waiting; restored to 5 |
| Unit UT-COP-13-B-08/09 | pass; full suite **984/984**; tsc clean |
| UI-COP-9-05-01 (extended, UI-COP-13-B-01) | pass: field shows the server value; 21 refused on screen, typing kept. Skills spec 7/7 |

**Differs from the epic / not proven:**
- Cap counted **per account, not per business**.
- **Scheduled runs don't step up:** only the chat re-runs on the strong copy; `run_for_business` still uses the standard copy only.
- **E-COP-093 / 095 not added:** declined and expired step-ups use the gate's own existing refusals.
- **Risk:** the strong copy re-does the whole request. If the standard copy already changed something before asking, the strong run could repeat it. The prompt says to ask instead of trying everyday work, but nothing on the server prevents a repeat.

### Story 02: Health lists each agent's model (2026-11-19, Sonnet 5.5)

**Built:** a manifest `src/health/agentModels.ts` (8 agents: name, one plain line, model) and an "AI models" panel on Health (`AgentModelsPanel`) with a summary line ("5 of 8 agents are on an older model") and an amber "older" tag on anything not in the Claude 5 family. No server call, no table, no Xano change. The older UT-COP-13-01..03 now read the same manifest, so there is one list only.

| Check | Result |
|---|---|
| Unit `agentModels.test.ts` UT-COP-13-02-01..06 | 6/6: every row matches its agent file (name and model); every agent file is listed; plain-word labels; older flagged; summary counts. Full suite **990/990**, tsc clean |
| UI-COP-13-02-01 (`health-agent-models.spec.ts`) | pass, screenshot checked. No test account is a platform admin (founder decision), so the browser is told the user is one and the other Health data is stubbed; the panel itself needs no server data |

**Not covered:** the manifest is kept by hand and checked against the repo files, not against what Xano actually has live (a live agent edited in Xano alone would not show). Step-up counts on Health (stories 04/05) are not built.

### Part B and story 02: not started (superseded above)

Story 02 (Health lists each agent's model) and the whole of part B (cheap and strong copy, "use a stronger model" approval, daily cap) are untouched. Part B adds an approval type and spends money, so it waits for the founder's go (README D-24-6).
