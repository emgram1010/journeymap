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

### Roll-out step 2a — the gate inside the live tools, report-only (2026-11-14, Fable 5.2)

**What is live now:** 36 of the 37 AI tools call `journey/tool_gate` as their first line and accept
an optional `ticket` input (`search_xano_docs` is left out: no customer data, used by the public
demo). All four switches in `usr/tool_gate_mode` are `report`, so **nothing is refused**; a
would-be refusal is logged (feature `COP-1`, step `tool_gate`, at most 60 rows an hour).

The gate now also knows **where** a call came from — `outside` (the tool address) or `inapp` (an
agent inside Emgram) — from the request address, which the caller cannot choose. Each has its own
read and write switch, so the outside path can be closed before the in-app one.

| Check | Result |
|---|---|
| All 36 tools have the gate and the `ticket` input (exact live copy, re-fetched) | ✅ 36/36 |
| Existing lines changed in the other 35 tools | ✅ none (line-for-line against the pre-change live copy) |
| `scaffold_structure` add / rename / remove / unknown key, on a test map | ✅ 8/8 **after the fix below** |
| 9 more tools run for real on a test map (read-back confirmed the writes) | ✅ `get_map`, `update_cell`, `batch_update`, `get_slice`, `get_gaps`, `update_stage_contract`, `update_journey_settings`, `update_actor_identity`, `list_maps` |
| In-app chat, one read turn and one write turn as a test user | ✅ both answered; the write landed |
| Gate log shows the right context | ✅ `outside` for the tool address, `inapp` for the chat |
| The remaining ~25 tools | Not run individually — covered only by "no existing line changed" |

**🔴 A break I caused and fixed (about 25 minutes, 23:26–23:51 UTC).** I based each push on the
live source Xano returned. For `scaffold_structure` that text had **lost the protective brackets**
the original file has (`{key: ($op|get:"key":""), id: (…)}` comes back as
`{key: $op|get:"key":"", id: …}`), and pushing it back made rename and remove fail with
"Unable to locate var: rm.id". Restored from the repo copy plus the gate lines; proven 8/8.
A scan for the same shape (a bare `$x|filter:arg` as an object value, or mid `&&`/`||`/`?:`)
finds 17 lines in that file and **0 in the other 35 tools**.

**Rule learned (worth a CLAUDE.md line):** *the XanoScript that `getTool` / `listTools` returns is
not safe to push back as-is.* Xano drops brackets around a filter inside an object literal when
it shows the source, and that changes the meaning on re-save. Fetch live to **compare**; push from
the repo file. An oversized MCP result is saved to a file, which makes an exact compare possible.

**Found, not fixed (pre-existing):**
- `search_maps` fails with "Invalid pipe." — it uses `|lowercase`; the filter is `|lower`. Same
  text since 2026-06-04, so it has been broken since then. Belongs with story 06.
- 10 tools differ between the repo and live (`calculate_leakage`, `update_stage_contract`,
  `clone_scenario`, `fill_cells`, `publish_map`, `update_journey_settings`, `batch_set_status`,
  `scaffold_structure`, `batch_update`, `mutate_structure`). Each was patched on its own side, so
  the difference is unchanged. Which side is right is not established.
- `create_journey_map` still stamps owner 0 / account 0 (seen again on test map 236).

**Test data left on purpose (test account 13):** maps 235 and 236, both titled "… (safe to delete)".

### Still open before anything can be refused

1. **Tickets for the in-app chat.** The chat endpoint (api 52) must mint a ticket and tell the
   agent to pass it. That file is 138 KB / 3,809 lines; re-sending it through the push tool is
   risky given the bracket rule above. Options: (a) the founder pushes that one file from the
   Xano VS Code extension after a 10-line edit; (b) an interim check that needs no ticket.
2. **Before the outside path is switched to refuse:** tools that create things must stamp the
   caller's owner and account; `list_maps` / `search_maps` / `list_scenarios` must filter by
   account; maps 226–234 (account 0) need an owner, or the founder loses them through the tools.

### Roll-out step 2b — the outside door's three prerequisites (2026-11-15)

Done, with the gate still in `report` mode (nothing refused):

| Item | Result |
|---|---|
| Maps 227–234 and architecture 46 given an owner | ✅ moved to user 2 / account 2 (the founder). Map 226 was already theirs. Nothing in the system now has account 0 (checked both maps and architectures) |
| Tools that create things stamp the caller | ✅ `create_workspace`, `create_journey_map`, `clone_scenario` — owner and account come from the caller; an `account_id` sent by the model is ignored |
| Lists show only the caller's account | ✅ `list_maps`, `search_maps`, `list_scenarios`, using the same `journey/visible_map_ids` the screens use |
| Gate also checks "is this business yours" | ✅ `journey_architecture_id` added to `journey/tool_gate`; same "not found" answer as for one that does not exist |
| `search_maps` "Invalid pipe." | ✅ fixed (`|lowercase` → `|lower`); it had been broken since 2026-06-04 |

**Real HTTP test, `tests/cop1_outside_probe.py`, test user in account 13, report mode: 12/12.**
Workspace and both kinds of map stamped to the caller; lists show only own maps; another account's
business lists nothing; a clone is owned by its maker; `search_maps` runs.

**Not yet run:** the same script with `COP1_EXPECT=enforce` (cross-account read, write and create
must be refused, with the same answer as a map that does not exist). That is the check to run
right after the switch below.

**To switch the outside door to refuse:** set `outside_read` and `outside_write` to `"enforce"` in
`usr/tool_gate_mode` (fn 310). Rollback is the same edit back to `"report"`. Any assistant on the
tool address (including the founder's) is then limited to its own account's maps.

Test data left in test account 13: maps 235 and 236 plus the probe's "(safe to delete)" workspace
and maps.

### Roll-out step 3 — the outside door refuses (2026-11-15, Sonnet 5.5)

`usr/tool_gate_mode` now reads `outside_read: enforce`, `outside_write: enforce`,
`inapp_read: report`, `inapp_write: report`. Rollback: set the first two back to `report`.

`tests/cop1_outside_probe.py` with `COP1_EXPECT=enforce`, test user in account 13: **16/16.**
Another account's map: read, write and create are refused with the same "not found" answer as for
a map that does not exist; another account's business is refused; the caller's own maps still
work; lists show only their account.

In-app chat, one read turn and one write turn after the switch: see the result below.

**What changed for the founder:** an outside assistant now sees only the account its token
belongs to, and needs a token at all (SEC-3). The in-app chat is unchanged until tickets are wired.
