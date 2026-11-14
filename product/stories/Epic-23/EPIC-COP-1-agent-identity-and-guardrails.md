# EPIC-COP-1 — Agent identity and guardrails

**Status:** 🚧 In progress (Fable 5.2, 2026-11-14). The gate is built and proven on throwaway copies (roll-out step 1). **No live tool calls it yet.** See section 7.
**Model:** **Opus 5.5** (or Fable 5.2). Guards and tenancy. Story 06 is Sonnet 5.5. Review pass after.
**Depends on:** SEC-3 (the tool door), USR-2 (access gates, live). Closes map 226 gaps 2, 3 and 4.
**Risk:** high. A mistake here lets an AI act on the wrong customer's data, or locks the chat out.

---

## 1. Goal

**Pain:** an AI in Emgram is nobody. Maps it creates have owner 0. Its tools skip the access gates
that now stop people. The log does not say who acted. There is no way to switch it off.

**Fix:** the copilot gets its own identity, goes through the same doors as a person, is pinned to
one business per session, logs every call with its name, and has an off switch and a daily cap.

**Win:** the owner can trust it with planning and doing — and can prove afterwards what it did.

---

## 2. Design

```
                       ┌────────── one shared check, in one function ──────────┐
Chat / scheduled run   │ 1. Who is acting?      (agent identity, switched on?) │
Outside assistant ───▶ │ 2. May it use this module? (same grants as people)    │ ──▶ the tool runs
(any caller)           │ 3. Is the target inside its business? (pinned scope)  │ ──▶ one log row: who,
                       │ 4. Is it under today's cap?                           │     tool, target, outcome
                       └───────────────────────────────────────────────────────┘
                                 any "no" → friendly refusal + a logged event
```

- **One door for every caller.** In-app chat, a scheduled run and an outside assistant all pass the
  same function. No tool does its own permission check.
- **Identity is visible.** The copilot appears on Manage users as kind "AI", with a name, and is
  switched off there like a person.
- **Pinned scope.** A session names one business architecture. A tool call aimed at anything
  outside it is refused, not silently redirected.
- **The log is the audit trail.** One row per call, from any caller, readable on Health.

---

## 2a. Design note — how a tool learns who is calling (probed live 2026-11-14, Fable 5.2)

Proven with a throwaway tool, tool address, agent and endpoint (all deleted afterwards):

| Where the tool runs | What the tool can see | So the caller is found by |
|---|---|---|
| Outside assistant, over the tool address | `$auth` is **empty**. The request's `Authorization` header and address (`?token=`) **are** visible | Checking that token — the same `usr/mcp_caller` the door uses |
| Inside Emgram, run by an agent from a signed-in endpoint | `$auth` is **empty**. **No** `Authorization` header (it is an internal call). The tool knows nothing about the caller | A **run ticket** (below) |

**The run ticket.** Before an endpoint runs an agent, it writes one row: a random id, the signed-in
user, their account, the map/business the turn is about, and an expiry. It gives the agent the
ticket id to pass to every tool (exactly how `turn_id` is passed today). The tool looks the ticket
up. The model cannot forge one, and a ticket only ever grants what its own user may reach — so a
model tricked by text in a cell into asking for another account's map is refused by the server.

**One gate, called first by every tool:**

```
tool starts ─▶ usr/tool_caller(ticket)            who is this?  header/address token, else ticket, else refuse
            ─▶ usr/assert_module_access            switched on + Intelligent Layer   (existing)
            ─▶ journey/assert_map_owner            is this map in the caller's account?   (existing)
            ─▶ the tool's own work, stamping owner + account from the caller, never 0
```

- New: `usr/tool_caller`, one small ticket table, and one wrapper `journey/tool_gate` that makes the
  three calls. Everything else is reused.
- Lists (`list_maps`, `search_maps`, `list_scenarios`) are filtered with the existing
  `journey/visible_map_ids`.
- 37 tools get the same first line. Endpoints that run an agent (list them with
  `grep -rl "ai.agent.run"`) mint a ticket.

**Roll-out, so the live chat cannot break:** (1) build and prove the gate on scratch copies;
(2) add it to the read tools in **report-only** mode (logs what it *would* refuse, refuses
nothing) and replay real chat turns; (3) switch to refusing, one tool group at a time, write
tools last; (4) probe: account A's token and ticket cannot read or change account B's map.

**Known wrinkles**
- Maps 226–234 and architecture 46 have account 0, so under this rule **nobody** can reach them
  through a tool until they are given to the founder's account. That is a data change — ask first.
- Each outside tool call costs one extra token check (~0.1–0.2 s).
- `build_journey_map` runs an agent from inside a tool; it must pass its own caller on as a ticket.

## 3. Stories

### US-COP-1-00 — 🔴 The map tools answered with no sign-in
**Status:** Moved to its own epic: `EPIC-SEC-3-lock-the-ai-tool-door.md`. Do that first.

### US-COP-1-01 — The copilot has its own identity
**Status:** 📋 Not started.

**As an** owner, **I want** the copilot to be a named member of my account,
**so that** everything it creates says who made it.

```gherkin
Scenario: Work is stamped with the copilot
  Given my account has a copilot named "Copilot"
  When it creates a draft map
  Then the map's owner is the copilot and its account is my account
  And nothing it creates has owner 0 or account 0

Scenario: It shows on Manage users
  When I open Manage users
  Then I see the copilot listed as kind "AI", with its name and whether it is on

Scenario: One copilot identity per account
  When a second identity is created for the same account
  Then it is refused with a friendly message
```

**Build notes.** First task is a short design note (Opus): where the identity lives.
`agent_profile` (kind `ai`, `user_id = 0`) already exists for the planner; `user` carries text
validators, so **no new column on `user`** — use a side table with its own GET endpoint. Decision
D-3. Existing rows with owner 0 (architecture 46, maps 226–234) are **not** rewritten here; list
them in Test Results and ask.

### US-COP-1-02 — Tools go through the same gates as people
**Status:** 📋 Not started.

**As an** owner, **I want** the copilot stopped by the same rules that stop a person,
**so that** a limit I set actually limits it.

```gherkin
Scenario Outline: A tool is refused when the grant is missing
  Given the copilot does not hold the "<module>" grant
  When it calls a tool that belongs to "<module>"
  Then the call is refused with a friendly message and code
  And nothing is written
  Examples:
    | module            |
    | Intelligent Layer |
    | Planner           |
    | Execution         |

Scenario: Granted tools keep working
  Given the copilot holds the Intelligent Layer grant
  When it reads a map in its business
  Then the call succeeds exactly as before

Scenario: Today's in-app chat is not broken
  Given a person using the existing map chat
  When they send a message that edits a cell
  Then it works as it does today
```

**Build notes.** Today "AI/MCP tools call functions directly and bypass every gate" (USR-2 commit
`2f8bdeb`). Reuse `usr/assert_module_access`; do not write a second copy of the rule. Map every
tool to exactly one module in **one** table/list, with a test that fails if a new tool is added
without one. Capture a before/after replay of the existing chat's tool calls.

### US-COP-1-03 — Pinned to one business at a time
**Status:** 📋 Not started.

**As an** owner with more than one business, **I want** the copilot working on one business per
session, **so that** it never mixes them.

```gherkin
Scenario: A call outside the pinned business is refused
  Given a session pinned to business A
  When the copilot calls a tool with a map that belongs to business B
  Then the call is refused and nothing is read or written

Scenario: Another account is never reachable
  Given a session in my account
  When a tool is called with a map id from a different account
  Then the answer is "not found", the same as for a map that does not exist

Scenario: Its own "how I work" maps are readable from any session
  Given a session pinned to business A
  When the copilot reads one of its own operating maps
  Then it succeeds, read-only
```

**Build notes.** One function, `copilot/assert_scope` (name to be confirmed), called by the shared
check. Resolve every target (map, plan, job, task) to its architecture, then compare. "Not found"
for other accounts, never "forbidden" — do not confirm that an id exists.

### US-COP-1-04 — Every tool call is logged with who
**Status:** 📋 Not started.

**As** the only support person, **I want** one log row for every tool call, naming who acted,
**so that** I can explain afterwards what the copilot did.

```gherkin
Scenario: Any caller leaves a row
  When a tool is called from the in-app chat, a scheduled run, or an outside assistant
  Then one row records who acted, the tool, the target, and whether it worked

Scenario: A refusal is logged too
  When a call is refused by a gate
  Then a row records the refusal and its reason code

Scenario: The log never holds secrets
  When a tool is called with a password, token or key in its input
  Then the row stores a short summary, not the value
```

**Build notes.** `agent_tool_log` exists but has no actor field and is written by only some tools
(map 226: 17 of 37, none with who — **re-count before building**). Add the actor through a side
table or a new log table (design note; `agent_tool_log` has no text validators — check with
`getTableSchema` before choosing). One shared logging step; the per-tool wiring is Haiku work.
Surface on the Health page under its own feature code.

### US-COP-1-05 — An off switch and a daily cap
**Status:** 📋 Not started.

```gherkin
Scenario: Switched off stops it on the next call
  Given the copilot is working
  When I switch it off on Manage users
  Then its next tool call is refused and it tells me it is paused

Scenario: A scheduled run does nothing while it is off
  Given the copilot is switched off
  When a scheduled run starts
  Then it ends at once and logs "skipped — switched off"

Scenario: The daily cap pauses it politely
  Given today's cap is reached
  When I ask it for something
  Then it says "I'm paused until tomorrow" and nothing else runs
  And Health shows one "cap reached" event, not hundreds
```

**Build notes.** No `redis.*` on this plan: count rows in the tool log since midnight with
`db.query … return = {type: "count"}`, cutoff computed into a `var` first. Decision D-7 sets the
cap; store it per account in a side table.

### US-COP-1-06 — The four map-tool bugs are fixed
**Status:** 📋 Not started. **Model: Sonnet 5.5.**

```gherkin
Scenario: Adding a stage without a primary actor works
  When a stage is added with no primary actor
  Then it is created, with the actor left empty

Scenario: A failed scaffold changes nothing
  When one step of a scaffold fails
  Then no stage, row or cell from that call is saved

Scenario: Intent is saved
  When a map is created or its settings are updated with an intent
  Then reading the map back shows that intent

Scenario: A new map belongs to someone
  When a map or architecture is created through a tool
  Then its owner and account are the caller's, never 0
```

**Build notes.** Found live 2026-11-14 (map 226 stage 3; update file "Problems hit"). The two
reports **disagree** on whether a failed scaffold half-saves — reproduce first. Each bug gets a test
that fails before and passes after. Crash text: `Unable to locate var: op.primary_actor_lens` — the
"bare missing key throws" rule in CLAUDE.md; read it through `??` into a `var`.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | Side tables only. Each new one: primary key, `created_at`, declared and indexed references, a unique index where "one per account" is the rule |
| Delete behaviour | The copilot identity is switched off, **never deleted**, once it has created anything |
| Validation | Friendly message + code on every refusal; the caller's text is kept |
| Error codes | `E-COP-001` not granted · `E-COP-002` outside this business · `E-COP-003` switched off · `E-COP-004` daily cap reached · `E-COP-005` tool has no module (a build mistake). Add to `errorCatalog.json`, feature `COP-1` |
| Events | Success and failure for: identity created, switched on/off, scope refusal, cap reached |

## 5. Counter-measures (so this does not break something else)

| Risk | Counter-measure |
|---|---|
| The existing map chat stops working | Before/after replay of its tool calls; the gate is added behind a flag and switched on per tool group |
| The 37 tools drift (a new tool with no gate) | A test fails when a tool has no module mapping |
| The gate leaks ids across accounts | Other-account ids always answer "not found" |
| The log fills with duplicates on a retry loop | Cap event is written once per day per account (count before insert) |
| Old owner-0 rows become invisible | Listed and reported, not rewritten, in this epic |

## 6. Test plan

| ID | Kind | What |
|---|---|---|
| FT-COP-1-01 | HTTP | Each module × each grant state → allowed/refused matrix, like `usr2_*_matrix.py` |
| FT-COP-1-02 | HTTP | Cross-business and cross-account targets → refused / not found |
| FT-COP-1-03 | HTTP | One log row per call from each of the three callers; refusal rows; no secrets |
| FT-COP-1-04 | HTTP | Switch off → next call refused; cap → paused, one event |
| FT-COP-1-05 | Function | Four tool bugs: fail before, pass after |
| UI-COP-1-01 | Browser | Manage users shows the copilot as "AI"; switch it off and on |
| REG | Suites | `npm test`, `tsc`, build; USR-2 matrices still 15/15 and 16/16; existing chat replay identical |

## 7. Test results

### Roll-out step 1 — the gate, on throwaway copies (2026-11-14, Fable 5.2)

**Pushed to Xano (workspace 1), attached to nothing live:**

| What | Id |
|---|---|
| Table `tool_run_ticket` (new) | 143 |
| `usr/mint_tool_ticket` | fn 308 |
| `usr/tool_caller` | fn 309 |
| `usr/tool_gate_mode` — currently `read: report, write: report` | fn 310 |
| `journey/tool_gate` | fn 311 |

**Matrix, run through `journey/tool_gate` with real run tickets (test account 13):**

| # | Case | Report mode | Enforce mode |
|---|---|---|---|
| 01 | Granted user, own map | ✅ ok | ✅ allowed |
| 02 | Granted user, another account's map | ✅ `E-COP-002` | ✅ refused |
| 03 | Granted user, map that does not exist | ✅ `E-COP-002` (same answer as 02) | ✅ refused |
| 04 | Granted user, no target map | ✅ ok | ✅ allowed |
| 05 | User without the Intelligent Layer | ✅ `E-COP-001` | ✅ refused |
| 06 | Switched-off user | ✅ `E-COP-001` | ✅ refused |
| 07 | Expired ticket | ✅ `E-SEC-020` | ✅ refused |
| 08 | Made-up ticket | ✅ `E-SEC-020` | ✅ refused |
| 09 | No ticket and no token | ✅ `E-SEC-020` | ✅ refused |
| 10 | Granted user, map with no account (226) | ✅ `E-COP-002` | ✅ refused |

Enforce mode was switched on only for that run and switched back; the function is in `report`.

**The gate inside a real tool, reached both ways (throwaway tool, tool address, agent, endpoint):**

| Path | Case | Result |
|---|---|---|
| Outside assistant, `Authorization` header | own map | ✅ ok, `via: token` |
| Outside assistant, `Authorization` header | another account's map | ✅ `E-COP-002` |
| Outside assistant, `?token=` | own map | ✅ ok |
| Outside assistant, no token | any map | ✅ `E-SEC-020` |
| In-app agent with a run ticket | own map | ✅ ok, `via: ticket` (the model passed the ticket correctly) |
| In-app agent with a run ticket | another account's map | ✅ `E-COP-002` |

**Cleaned up:** throwaway tools 159/160, tool addresses 34/36, agents 35/37, endpoints 631/632,
function 312 and all test tickets are deleted. **Left on purpose:** map 235, "COP-1 fixture (safe
to delete)", in test account 13 — the probes for steps 2–4 need a map that account owns.

**Learned (for CLAUDE.md):** `$env.$http_headers` and `$env.$request_uri` work inside a function
called from a tool. When a function is run through the Xano management connection
(`runWorkspaceFunction`), that connection's own `Authorization` header is visible to it — so a
"no token" test run that way reports `bad_token`, not `no_token`. Harmless, but do not read it as
a bug.

### Not done yet

- Step 2: add the gate's first line to the 37 tools in report mode; endpoints that run an agent
  mint a ticket and tell the agent to pass it. **Touches the live chat — ask first.**
- Step 3: switch to refusing, read tools first.
- Step 4: cross-account probe over real HTTP on the real tools.
- Stories 01 (identity), 04 (log with who), 05 (off switch and cap), 06 (tool bug fixes).
