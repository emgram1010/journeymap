# EPIC-COP-14 — "Emgram operations": Emgram maps its own way of working, in Emgram

**Status:** 📋 Not started
**Model:** **Sonnet 5.5** for 01, 02 and 04. **Opus 5.5** for story 03: planner tools on the outside door are a permission change. Opus review of story 03.
**Depends on:** COP-10 (the publish checklist tool). Story 03 depends on SEC-3 / COP-1 (the MCP door and its gate).
**Risk:** low for the map. Medium for story 03, which opens planner tools to outside assistants.

---

## 1. Goal

**Pain:**
- Emgram's own way of working lives in chat threads and in the founder's head: who does the thinking (you or the copilot), which model, and when to ask.
- The AI API isn't cheap. The founder's Max plan covers their own use of Claude, but there's no settled flow for when to use it and when to use the in-app copilot.
- We have never built a real map, end to end, the way a customer would. So platform gaps only show up when a customer hits them.

**Fix:**
- Make a business called **"Emgram operations"** in the founder's account.
- Its first map is **"Who does the thinking"**, built by Claude on the founder's Max plan through Emgram's own MCP door.
- It passes the same publish checklist as any customer map.
- Every gap we hit is logged as a product bug, never worked around by hand.

**Win:**
- The rule for "Max plan or paid API" is written down as a published map, not a chat.
- Emgram is proven on itself.
- Each gap found becomes a fix that customers benefit from too.

### The split this map writes down (from the founder conversation, 2026-11-18)

| Who thinks | When | Pays with | Examples (illustrations only) |
|---|---|---|---|
| **The founder, with Claude on the Max plan** through Emgram's MCP door | Someone is at the keyboard | Max plan (the founder's own use only) | A strategy session that drafts maps; weekly planning from last week's results |
| **The in-app copilot** on the paid API, cheap model first | No one is present, or a customer's own business | API credit, priced into the customer's subscription | The 6 a.m. scheduled check; a customer's own copilot; an alert for a step blocked for 2 days |

**Always the same:** Emgram is the system of record. Every change goes through the same gate, the same approval levels and the same log, whichever AI makes it. A person still presses **Publish version** and **Publish to live**.

**Limit stated in the map:** the Max plan covers the founder's own use. It never powers a customer's copilot.

---

## 2. Stories

### US-COP-14-01 — The "Emgram operations" business

**As** the founder **I want** Emgram's own operations in their own business **so that** they never mix with the copilot's "How I work" or with test data.

```gherkin
Scenario: a business of its own
  Then a business "Emgram operations" exists in the founder's real account (not test account 13)
  And it is not the copilot's own business, and it is not used for tests

Scenario: same rules as a customer
  Then it gets no special permissions, flags or shortcuts
```

### US-COP-14-02 — The map "Who does the thinking", built through the MCP door

**As** the founder **I want** the first map built the way a customer's AI would build it **so that** the front door is proven.

```gherkin
Scenario: built through MCP on the Max plan
  When Claude (desktop or Code, Max plan) connects to Emgram's journey_map MCP server with the founder's own sign-in
  Then it creates and fills the map only through MCP tools: no direct database writes, no Xano dashboard edits

Scenario: what the map holds
  Then it has two branches: "Founder with Claude (Max plan)" and "In-app copilot (API)"
  And each stage has an owner role, a task, a duration and a checkable "done when"
  And one stage records the model rule: the cheapest model that passes, step up only with approval (COP-13)

Scenario: it passes the real checklist
  When Claude calls check_publish_ready (COP-10)
  Then the map shows ready = true before the founder presses Publish version
  And the founder, not the AI, presses Publish version

Scenario: labelled
  Then the map is labelled kind "runnable" (COP-4-04), so it reads as a process, not research
```

### US-COP-14-03 — The founder can plan through the MCP door too

**As** the founder **I want** Claude on my Max plan to reach planning, not just maps **so that** weekly planning doesn't spend API credit.

```gherkin
Scenario: the gap today (verified 2026-11-18)
  Given the journey_map MCP server lists map tools only
  And the planner tools (plan_create, plan_add_job, plan_schedule_card, ...) exist only for the in-app copilot
  Then outside assistants can't plan

Scenario: planner tools on the MCP door
  Then the planner tools are added to the MCP server, behind the same auth gate (SEC-3) and journey/tool_gate
  And they act as the signed-in person, under that person's permissions, not as the copilot

Scenario: Publish to live stays a button
  Then no MCP tool publishes a plan to live (Epic-23 decision D-4)
```

### US-COP-14-04 — Every gap becomes a bug, not a workaround

**As** the founder **I want** each problem found while building this map recorded **so that** customers get the fix too.

```gherkin
Scenario: a gap is found
  When a tool can't do what the map needs, or gives a confusing error
  Then the gap goes in this epic's "Gaps found" list with the tool, what was tried and what happened
  And the map is not finished by hand around it

Scenario: the list is read
  Then the gaps are reviewed with the founder before the next epic is chosen
```

### US-COP-14-05 — Claude on the Max plan reads "How I work" through MCP

**As** the founder **I want** Claude to follow the same skills as the copilot **so that** both AIs build the Emgram way.

```gherkin
Scenario: a read-only skills tool on the MCP door
  Then the journey_map MCP server has get_how_i_work, which returns copilot/skill_library's text for the signed-in person's account
  And it is read-only: no save, edit or retire over MCP (the copilot stays the only writer)

Scenario: told to read it first
  Then the MCP server's instructions say: call get_how_i_work before building or planning
```

### US-COP-14-06 — Where outside-app connections live (decision, 2026-11-18)

**As** the founder **I want** a clear rule for where connections like Booqable go **so that** Emgram doesn't become a hodgepodge.

```gherkin
Scenario: a tool for the founder
  Given a connection only the founder uses with Claude on the Max plan
  Then it lives in a separate Xano "connectors" workspace with its own MCP server
  And Claude joins the two: reads the connectors workspace, writes Emgram through Emgram's MCP; the workspaces never call each other
  And it holds only the founder's own business keys and data, never a customer's

Scenario: a feature customers use
  Given customers' copilots need the connection
  Then it moves into Emgram's connections library (COP-6), with per-business encrypted logins and approval levels
```

### US-COP-14-07 — A guardrails map (review results, not steps)

**As** the founder **I want** the oversight rules written down as a map **so that** they still hold when the AI outgrows reviewing each change.

```gherkin
Scenario: the map "How we stay in control"
  Then "Emgram operations" has a second map stating:
  | rule |
  | judge the AI on results (plan vs actual), not on each edit |
  | the owner sets goals and limits; the AI chooses how |
  | every step small and undoable (trial, versions, Undo) |
  | big changes checked by a second AI that only flags, never approves |
  | money, customer messages and publishing stay a button a person presses |
  And it passes check_publish_ready like any map
  # the second-AI checker is a future epic; this story only writes the rule down
```

---

## 3. Governance

- **Tables:** none new. The business and map are ordinary rows created through the product.
- **Changed live items (story 03 only):** MCP server `journey_map` (tool list), possibly the planner tools' gate calls. Fetch the live source first; git HEAD is the rollback. **Ask before the push.**
- **Validation:** the existing tool and gate rules. Nothing special for this business.
- **Error codes:** none new expected. A refusal on the MCP door reuses SEC-3 / COP-1 codes.
- **Events:** the existing tool and publish events. The proof is that this business's events look exactly like a customer's.
- **Delete behaviour:** the normal business guards.

## 4. Counter-measures

| Risk | Counter-measure |
|---|---|
| Max plan used to power the product | The map says so, and only the founder's own sign-in builds it. Customer copilots use the API (COP-13) |
| Planner tools on the outside door widen access | Same auth gate and tool_gate, acting as the person; Opus review; no Publish to live tool |
| Gaps quietly fixed by hand | Story 04: log it and stop. No dashboard edits |
| Test data mixed in | Real account, its own business, never account 13 |
| The founder's token shows up in a log or chat | Never printed. The sign-in stays in the Claude connector settings |

## 5. Test plan

| ID | Type | Checks |
|---|---|---|
| FT-COP-14-01 | Function | The business exists in the founder's account and is not the copilot's own business |
| FT-COP-14-02 | Real AI (Max plan, MCP) | The map is built only through MCP calls (tool_call_log shows the founder as caller, source MCP) |
| FT-COP-14-03 | Function | check_publish_ready true, then the founder publishes; published version exists |
| FT-COP-14-04 | Function | Story 03: planner tools listed on the MCP door; refused with no sign-in; no publish-to-live tool |
| FT-COP-14-05 | Function | get_how_i_work over MCP returns the account's skills; refused with no sign-in; no write tool exists |
| FT-COP-14-07 | Function | The guardrails map passes check_publish_ready |

## 6. Gaps found

- **2026-11-18, story 05 built early (the tool, not the build).** `get_how_i_work` (tool 187) and COP-10's `check_publish_ready` (tool 186) are on the `journey_map` MCP server (22 → 23 tools listed; server pushed from `ai/mcp_server/journey_map.xs`, instructions updated). Proven over the real door as the test admin: `tools/list` shows both; `check_publish_ready` on map 261 returned ready with 2 of 2; `get_how_i_work` returned the account's 4 skills; no token still refused (SEC-3 probe 3/3). Not yet run with Claude on the Max plan and the founder's own sign-in.
- **The MCP door exposes `publish_map`.** An outside Claude signed in as the founder can publish a version itself, which is not the rule in "Always the same" above ("a person presses Publish version"). For the copilot the gate refuses it (E-COP-025); for a person's token it does not. **Decided 2026-11-19 (founder): keep it** - the founder is the person, so an outside Claude signed in as them may publish a version. Not changed.

## 7. Test results

### Story 03: planner tools on the outside door (2026-11-19, Opus 5.5; founder approved the permission change)

**Built:**
- The 10 planner tools are on the `journey_map` MCP server (23 -> 33 tools), with a "Planning (drafts only)" section in its instructions. No tool publishes a plan to live.
- Each planner tool takes an optional `journey_architecture_id` and passes it to `journey/tool_gate`, which already refuses a business outside the caller's account.
- ONE new rule, `copilot/work_business` (function 406): the chat's pinned business always wins; only a caller signed in by token (the outside door) may name one; anything else = 0 and the tool refuses with E-COP-045 (new message says to pass `journey_architecture_id`).
- Unchanged on purpose: approval levels still apply to AI identities only (a person is never stopped), and an AI with no pin is still refused (E-COP-048) even if it names a business. The gate itself was not edited.

| Check | Result |
|---|---|
| Unit `cop14PlanDoor.test.ts` UT-COP-14-03-01..05 | 5/5; full suite **997/997** |
| `copilot/work_business` live | token + named 49 -> 49; ticket + named 49 -> 0; pinned 48 -> 48 |
| Real door (`tests/cop14_plan_door_probe.py`, test admin, no AI) | **8/8**: signed in lists all 10; no publish-to-live tool; no sign-in lists nothing; no business -> E-COP-045 with the fix; another account's business refused; `plan_create` -> plan 143, `plan_add_person`, `plan_start_day` made a draft day |

**Known gap, not fixed:** an EMPTY plan (no map accepted yet) is tied to no business, so its creator can change it while naming another of their own businesses. That is the shared rule `copilot/plan_in_business` ("an empty plan is allowed only for its creator"); the in-app copilot behaves the same. Once the plan accepts a map it is bound.
**Not run:** the in-app copilot planning after this change (the rule returns the pinned business unchanged, proven on the function, not in a real chat); Claude on the founder's Max plan (needs the founder's token). Test plans 142 and 143 are throwaways.
