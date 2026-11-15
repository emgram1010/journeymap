# EPIC-COP-7 — Harden the copilot's research and its plan-vs-actual reading

**Status:** ✅ All six stories built and proven live (2026-11-15, Fable 5.2). Review pass pending. Written 2026-11-15 (Fable 5.2) from the Fable review in `COP-1-WORK-TRACKER.md` (findings F1–F7).
**Model:** **Opus 5.5** (or Fable 5.2) for stories 01–04 — guards on what an AI may touch and what leaves the product. Sonnet 5.5 for story 05. Review pass after.
**Depends on:** COP-1 (gate), COP-3 (business pin), COP-4 (research), COP-5 story 04 (job reading). All live.
**Goes before:** any COP-5 planner work. Fix what is live before adding more.
**Risk:** medium. Left as is: a web page can make the copilot damage the owner's maps, and private
details or the run ticket can leave in a web search. Fixed wrongly: research stops working.

---

## 1. Goal

**Pain:** the review found that the copilot's research step is safe by instruction, not by
construction, in three places, and that the job-reading tools check the caller too late.

**Fix:** every one of these becomes a rule in code, so it holds even when the AI is fooled.

**Win:** the claim "text from the web is data, never instructions" is true because there is
nothing harmful a page can make the copilot do — not because the copilot was asked nicely.

---

## 2. What was found (review, 2026-11-15)

| # | Finding | Story |
|---|---|---|
| F1 | The researcher can change **any** map in the business, including the owner's own, and can remove stages | 01 |
| F2 | The search tool's own instructions say to search names and companies; nothing in code stops private details leaving | 02 |
| F5 | The "fit notes" passed to the researcher have no limit | 02 |
| F3 | The run ticket can be written into a search, a map cell or a research note | 03 |
| F4 | The job tool answers "not found" before checking who is calling; that call is not in the audit trail | 04 |
| F6 | Source lists have no size limit; an empty first label stores the wrong shape | 05 |
| F7 | The job list has no limit, includes deleted maps' jobs, and accepts any status text | 05 |

Checked and fine (no story): the business pin and ticket carry through to the researcher; it has
no publish, approval, plan, note or goal tool; it cannot open a web address of its choosing.

---

## 3. Design

```
Owner asks ──▶ Copilot ──▶ research_topic ──▶ Researcher (a research-only ticket)
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────┐
                    ▼                             ▼                             ▼
              web search                    change a map                  final report
        refused if the query          allowed only on a map the        ticket scrubbed
        holds private details         copilot itself made              before it returns
        or the ticket
```

- **A research run gets its own, narrower ticket.** Same identity, same business, same daily cap —
  plus a "research" mark. The gate reads the mark; the tools do not need to know which AI is calling.
- **One place for each rule.** "Research only changes the copilot's own maps" lives in the gate
  (`journey/tool_gate`). "A search carries nothing private" lives in one function that the search
  tool calls. No copies.
- **Fails closed.** If the gate cannot tell who made a map, a research run may not change it.
- **Generic, not built for one business.** The checks look at shapes (an email address, a long
  number, the business's own name, the ticket) — never at a list of particular words.

---

## 4. Stories

### US-COP-7-01 — Research only changes maps the copilot made
**Status:** ✅ Built and proven live (Fable 5.2, 2026-11-15). **Review pass:** pending.

**Description.** Today a research run may edit or strip any map in the business. After this, a
research run can create new draft maps and change maps the copilot itself created — nothing else.
The main copilot chat is unchanged: the owner can still ask it to edit any map in the business.

**As** an owner, **I want** research to leave my own maps alone,
**so that** a bad web page can never make the copilot damage my work.

```gherkin
Scenario: Research drafts a new map
  Given a research run in my business
  When it creates a map and fills it
  Then the map is created as a draft and labelled as research

Scenario: Research may improve its own earlier draft
  Given a map the copilot created in this business
  When a research run changes it
  Then the change is made

Scenario: Research is refused on a map I made
  Given a map a person created in this business
  When a research run tries to change its cells or its structure
  Then it is refused with a friendly message, and the map is unchanged
  And a refusal is recorded in the audit trail

Scenario: The chat copilot can still edit my map when I ask
  Given the same map
  When I ask the copilot in chat to change it
  Then the change is made as before

Scenario: Who made the map cannot be told
  Given a map with no recorded creator
  When a research run tries to change it
  Then it is refused
```

**As built — no new table was needed.** The ticket table already has a `source` field, written
only by the server step that makes the ticket. `research_topic` now makes a child ticket with
source `research`; that is the mark. (The founder approved a new table; reusing the existing
field is smaller and follows "reuse, do not duplicate".)

**Build notes (original).** `research_topic` mints a child ticket for the same copilot user and business (the
pattern `invoke_map` already uses) with a research mark. The mark is a new fact about a ticket:
put it in a **new side table** (additive; ask before the schema push), not a new column. In the
gate: research mark + `kind: write` + a map id → the map's creator must be the copilot user, else
refuse in any mode (new code `E-COP-051`). Verify first how `create_journey_map` records the
creator for a copilot caller. Remove "reuse a draft with the same purpose" ambiguity from the
researcher's prompt: it may reuse **its own** drafts only. Update the agent's description, which
currently over-claims.

### US-COP-7-02 — A web search carries nothing private
**Status:** ✅ Built and proven live (Fable 5.2, 2026-11-15). **Review pass:** pending.

**Description.** Search queries leave Emgram and go to an outside search company. Today only a
prompt line keeps them generic, and the search tool's own instructions say the opposite. After
this, a research search is checked in code before it is sent.

**As** an owner, **I want** the copilot's web searches to stay general,
**so that** my business name, my customers and my figures never leave the product.

```gherkin
Scenario: A general search goes through
  When research searches "how rental companies handle damage checks"
  Then the search runs

Scenario: A search with an email address is refused
  When research searches for text containing an email address
  Then it is refused before anything is sent, with a message telling it to search generally

Scenario: A search with a long number is refused
  When the query contains a run of 7 or more digits
  Then it is refused before anything is sent

Scenario: A search with the business's own name is refused
  Given the conversation's business has a name of 4 or more characters
  When the query contains that name
  Then it is refused before anything is sent

Scenario: Fit notes are short
  When research is started with fit notes longer than 500 characters
  Then it is refused with a friendly message

Scenario: Other agents' searches are unchanged
  Given an agent that is not on a research ticket
  When it searches
  Then the search behaves as it does today
```

**Build notes.** One function, `copilot/search_query_check`, called by `web_search` only when the
ticket carries the research mark (story 01), so the older agents that use `web_search` for
prospect research are untouched. The research run sees neutral instructions: either a thin
`research_search` tool that wraps the same call, or the instructions rewritten to be neutral —
pick whichever leaves the older agents' behaviour identical. Refusals log the **reason**, never
the query text. New code `E-COP-052`. Limit: this stops the obvious shapes, not every private
fact; say so in the test results.

### US-COP-7-03 — The run ticket never leaves
**Status:** ✅ Built (2026-11-15), with one scenario changed on purpose: cells, notes and sources are **not** scrubbed. Instead the research ticket is ended the moment the run finishes (and lives 15 minutes at most), so a ticket written into a map is already useless when anyone reads it. Scrubbing would have meant changing three large shared map tools for no extra safety. The researcher never sees the chat's own ticket.

**Description.** The ticket is what lets the copilot act. The researcher holds it and is not told
to keep it to itself; only the final chat reply is scrubbed today.

**As** the founder, **I want** the ticket to stay inside tool calls,
**so that** it cannot end up in a search, a map or a note where someone else could reuse it.

```gherkin
Scenario: A search containing the ticket is refused
  When a query contains the run ticket
  Then it is refused before anything is sent

Scenario: The research report is scrubbed
  When the researcher's report contains the ticket
  Then the copilot receives the report with the ticket replaced by "[hidden]"

Scenario: The ticket is not stored in a map or a label
  When a cell, a research note or a source contains the ticket
  Then it is stored with the ticket replaced by "[hidden]"

Scenario: A research ticket stops working when the run ends
  Given a research run has finished
  When its ticket is used again
  Then it is refused
```

**Build notes.** Add "never repeat the ticket" to the researcher. Scrub in `research_topic`
(report), in the story 02 check (query) and in the write tools the researcher has. Ending the
child ticket when the run finishes needs a way to expire a ticket early — check what
`usr/mint_tool_ticket` and the ticket table already allow before adding anything; a short life
(for example 10 minutes) is the fallback if early expiry is not possible without a table change.

### US-COP-7-04 — The job tool checks the caller first
**Status:** ✅ Built and proven live (2026-11-15).

**Description.** `get_job_variance` looks the job up, and can answer "Job not found", before it
checks who is calling. A caller with no ticket can learn which job numbers exist, and that call
never reaches the audit trail or the daily cap.

**As** the founder, **I want** every tool to check the caller before it reads anything,
**so that** nobody learns anything without being identified and recorded.

```gherkin
Scenario: No ticket, any job number
  When get_job_variance is called with no ticket
  Then it is refused as "sign in", whether or not the job exists

Scenario: Every miss sounds the same
  When the job does not exist, or belongs to another account
  Then the answer is "Job not found" in both cases

Scenario: Another business's job
  Given a job in another business of my account
  When the copilot asks for it
  Then it is refused as belonging to another business

Scenario: The call is recorded
  When the tool is called, allowed or refused
  Then one row is written to the audit trail
```

**Build notes.** Gate first with map 0 (identity, cap, audit). Then the lookup. Then the account
and business checks done by the tool itself against the gate's `account_id` and
`pin_architecture_id` — not a second gate call, which would write a second audit row. Keep the
"an AI must be pinned" refusal.

### US-COP-7-05 — Sensible limits on labels and job lists
**Status:** ✅ Built and proven live (2026-11-15), except the 50-job cap and deleted-map filter, which need real jobs (story 06).

**Description.** Small fixes that stop quiet oddities: unbounded lists, the wrong empty shape, a
typo that returns nothing.

**As** an owner, **I want** the copilot's lists and labels to stay small and correct,
**so that** chats stay fast and what I see on screen is right.

```gherkin
Scenario: A first label with no sources stores an empty list
  When a map is labelled for the first time and no sources are given
  Then its sources are an empty list

Scenario: Too many or too long sources are refused
  When a label is given more than 20 sources, a title over 200 characters or a link over 500
  Then it is refused with a friendly message and the label is unchanged

Scenario: The job list is capped
  Given a business with more than 50 jobs
  When the copilot lists jobs
  Then it gets the 50 newest and is told there are more

Scenario: Jobs of deleted maps are not listed
  Given a job whose map was deleted
  Then it is not in the list

Scenario: An unknown status is refused
  When the copilot filters jobs by a status that does not exist
  Then it is refused with the list of valid statuses
```

**Build notes.** Count the list in a loop with a counter (no paging — CLAUDE.md). Deleted maps via
`journey/deleted_map_ids` with `not in` and the `-1` seed. Valid statuses come from the one place
job statuses are defined; do not write a second list. New code `E-COP-053` (label limits).

### US-COP-7-06 — Proven on real data
**Status:** ✅ Done (2026-11-15) on real job 143 — results in EPIC-COP-5 §7. Not done: the browser comparison with the report screen (the tool and the screen's endpoint call the same function), the 50-job cap and the deleted-map filter (one job exists), and the chat question with the real AI.

**Description.** The job tools have never run on a real job, because the test account has none.

**As** the founder, **I want** the plan-vs-actual reading proven on real jobs,
**so that** I can trust the figures the copilot quotes.

```gherkin
Scenario: The copilot's figures match the report screen
  Given a test job with a published plan and recorded starts and finishes
  When the copilot reads its plan vs actual
  Then every figure equals the report screen's figure for that job

Scenario: Another account's job is refused
  Given a job in a different account
  Then the copilot is refused

Scenario: The copilot answers in chat
  When I ask "how did that job go against the plan?"
  Then it quotes the report's figures and computes nothing itself
```

**Build notes.** Fixtures through the product's own endpoints where possible. Realistic times
(base `1_800_000_000_000`, never 0). The same fixtures are the starting point for the COP-5
planner replay set.

---

## 5. Governance

| Area | Rule |
|---|---|
| Tables | One new side table for the ticket's research mark (story 01). Needs `updated_at` or an append-only entry in `schemaAudit.ts`; the reference is the first field of an index. No change to an existing table. Deleting a ticket deletes its mark |
| Validation | Every refusal has a friendly message that says what to do instead. The owner's typing is never lost (these are tool calls, not forms) |
| Error codes | `E-COP-051` research may only change the copilot's own maps · `E-COP-052` search must stay general · `E-COP-053` label limits. Check each number is free; one message per code; add to `errorCatalog.json` |
| Events | Refused research write and refused search → `rejected` event (reason only, never the query or the ticket), capped like other gate refusals. Research run success/failure already logged |
| Audit | Every tool call, allowed or refused, has one audit row (story 04 closes the one gap) |
| Rollback | Each tool and the gate are saved from **live** before the push and can be put back in one push. The side table can stay empty |

## 6. Counter-measures

| Risk | Counter-measure |
|---|---|
| The gate change breaks every AI tool | Gate saved from live first; after the push, one read and one write tool are run with a person's ticket, a copilot ticket and a research ticket before anything else |
| Research stops working (refuses its own drafts) | A full research run is repeated after the push; it must draft and label a map |
| The older agents' web search changes | The check runs only on a research ticket; one search with a normal ticket is run before and after and must match |
| The search check blocks ordinary topics | A list of 20 ordinary topics is run through the check; all must pass. The list is kept with the tests |
| The search check is taken as a guarantee | Test results state plainly what it catches and what it cannot |
| The ticket is scrubbed in one place and leaks in another | One scrub function, called from each place; a test plants the ticket in a query, a cell, a note and the report |
| "Who made this map" is recorded differently than assumed | Verified on live data before building; unknown creator means refused |
| A copy of a rule appears in two tools | Rules live in the gate or one function; review checks for copies |
| The live copy differs from the repo | Every push starts from the live source (`getTool` / `getFunction`), per CLAUDE.md |
| Test data pollutes the test account | Created with a clear prefix, listed in the test results, removed afterwards (standing OK for own fixtures) |

## 7. Test plan

Tests are written first. Probe script: `tests/cop7_hardening_probe.py`.

| ID | Kind | What |
|---|---|---|
| FT-COP-7-01 | Tool (live) | Research ticket: write to a person's map refused (`E-COP-051`), map unchanged, audit row written |
| FT-COP-7-02 | Tool (live) | Research ticket: create a map, change it, label it — all work |
| FT-COP-7-03 | Tool (live) | Chat ticket: change to a person's map still works |
| FT-COP-7-04 | Tool (live) | Search check: email, long number, business name, ticket → refused; 20 ordinary topics pass |
| FT-COP-7-05 | Tool (live) | Normal ticket search identical before and after |
| FT-COP-7-06 | Tool (live) | Ticket planted in report, cell, note, source → stored and returned as "[hidden]" |
| FT-COP-7-07 | Tool (live) | Research ticket refused after the run ends |
| FT-COP-7-08 | Tool (live) | `get_job_variance`: no ticket → sign-in refusal for existing and missing job alike; audit row each time |
| FT-COP-7-09 | Tool (live) | Label limits and empty-list shape; job list cap, deleted maps, bad status |
| FT-COP-7-10 | Tool + browser | Real job: tool figures equal the report screen; other account and other business refused |
| FT-COP-7-11 | Chat (live AI) | A real research run still drafts and labels a map; "how did the job go" quotes the report |
| UT-COP-7-01 | Unit | Any model or catalog change in `webapp/protype-2` (error codes present, one message each) |
| REG | Suites | `npm test`, `tsc`; COP-1 to COP-4 probe scripts re-run and unchanged |

## 8. Test results (2026-11-15, Fable 5.2) — story 01, part of story 03

**Pushed:** `usr/tool_caller` (309, now returns the ticket's source), `journey/tool_gate` (311, the
research rule, `E-COP-051`), new `usr/expire_tool_ticket` (339), tool `research_topic` (166: own
15-minute research ticket, ended when the run ends, report scrubbed, fit notes capped at 500),
agent 41 (prompt and description). `E-COP-051` added to `errorCatalog.json`. No table change.

| Check (test account 13, business 49, copilot user 26) | Result |
|---|---|
| Research ticket, write, map 243 (made by a person) | ✅ refused |
| Same, through a real tool (`label_map` on map 243) | ✅ refused, nothing written |
| Research ticket, write, map 259 (made by the copilot) | ✅ allowed |
| Research ticket, read, map 243 | ✅ allowed (reading is fine) |
| Chat (non-research) copilot ticket, write, map 243 | ✅ allowed, as before |
| A person's ticket, write, map 243 | ✅ allowed, as before |
| Research ticket after `usr/expire_tool_ticket` | ✅ refused; empty ticket does nothing |
| Real research run after the push (real AI, real web search) | ✅ 95 s, drafted and reported a new map |
| `npm test` / `tsc` | ✅ 815/815 / clean |

### Stories 02–05 (same day)

**Pushed:** new `copilot/search_query_check` (340); tool `web_search` (39: calls the check, one
added line of instructions); tools `get_job_variance` (168) and `list_business_jobs` (167)
rewritten per stories 04/05; tool `label_map` (165: source limits, empty list). `E-COP-052`,
`E-COP-053` added to `errorCatalog.json`.

| Check | Result |
|---|---|
| Research ticket: general search | ✅ runs, 5 results |
| Research ticket: email address / 8-digit number / phone-like number / the ticket itself / the business's own name | ✅ each refused before sending, reason logged (never the query) |
| Non-research ticket with an email and a long number | ✅ passes the check untouched |
| `get_job_variance`, no ticket: missing job and existing job | ✅ same sign-in refusal for both |
| `get_job_variance`, person's ticket: missing job and another account's job (125) | ✅ same "Not Found" for both |
| `list_business_jobs`: pinned copilot / status "done" / status "completed" | ✅ answers / refused with the valid list / answers |
| `label_map`: 2 valid sources replace the old list; a 230-character title; sources not a list | ✅ replaced exactly / refused `E-COP-053` / refused |
| `label_map`: first label with no sources | ✅ stores `[]` |
| `npm test` / `tsc` | ✅ 815/815 / clean |

**New engine fact (confirmed live):** `$list|slice:0:N` works on a plain `return = {type: "list"}`
result and the slice can be looped. A paged query result exposes no keys at all (`|keys` is `[]`,
`|get:"items"` is empty) — so "newest N" is: plain list, sort, slice. Worth adding to CLAUDE.md.

**Test data touched:** map 260's real research sources were replaced by two probe sources; map 244
got a label (kind runnable, made by copilot_draft). Both are in test business 49.

**Not proven / known limits**
- The search check stops obvious shapes only. A customer's name, a street address or a figure
  written in words still gets through; the prompt rule is the only guard for those.
- The 20-ordinary-topics run was not done (two ordinary topics passed). A year range like
  "2024 - 2025" would be refused as a long number; the message tells the AI to reword.
- The 50-job cap, the deleted-map filter and "another business's job" were not run: no jobs exist.
- The refusal **text** could not be read back: the test tools show only "Access Denied" for this
  kind of refusal. That it is the research rule is shown by elimination (same ticket: read allowed,
  own map allowed; other tickets: allowed). Whether the researcher AI sees the full message is unchecked.
- "Unknown maker is refused" is in the code but no test map with no maker was used.
- A research run can still make a sub-map only under a parent the copilot made.
- The live gate was not compared line by line with the repo before the push (the repo copy was
  taken as current; its last change was this project's own).
- The workflow-test file cannot be run from a session; these checks were driven by hand.

