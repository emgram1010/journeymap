# Handoff — finishing Epic-23 (the copilot)

Written 2026-11-15 at the end of the build session. To start, paste this one line into a new session:

> Read `product/stories/Epic-23/NEXT-SESSION-HANDOFF.md` and follow it. Start with section 1.

---

## 1. Before you touch anything

1. Read `CLAUDE.md` (the response format and the XanoScript traps are not optional).
2. Read this file to the end.
3. **Check whether the final Fable review has finished.** Open
   `product/stories/Epic-23/COP-1-WORK-TRACKER.md` and look for a section at the bottom titled
   `## Final Fable review (...)`.
   - **Not there yet:** the review is still running in another session. It compares live Xano objects
     against the repo. **Do not push anything to Xano until it is there** - ask the founder in one
     bullet whether the review is done. You may read, plan and write local files meanwhile.
   - **There:** read it first. Its findings (R1, R2, …) come **before** the work in section 4. Fix
     critical and high findings first; ask the founder before any fix that touches a live endpoint or
     an existing table if it is not already covered by the approvals in section 3.
4. Tell the founder in one line which model you are on. Guards, tenancy and live-endpoint changes are
   Opus 5.5 / Fable 5.2 work; say so if you are on something smaller, and wait.

## 2. Where things stand

Branch `new-ui`. Last commit when this was written: the handoff commit after `d10133a`. **Nothing is
pushed to GitHub** - do not push; the founder decides.

| Epic | State |
|---|---|
| COP-1, COP-2, COP-3 | Built, reviewed once |
| COP-4 | Built. Story 05: plan-vs-actual learning built (`get_map_learnings`, tool 177); "my edits teach it" not built |
| COP-5 | Built: 01 six planner tools + capacity warning, 03 its own tasks, 04 plan vs actual, 05 scheduled runs, 06 copilot as a column (screen only). **Not built:** see section 4 |
| COP-6 | Not started - needs new tables and founder decisions (section 5) |
| COP-7 | Built and proven; under review now |

Suites when this was written: `npm test` 830 of 830, `tsc` clean (`webapp/protype-2`). Playwright and
`workflow_tests/` were **never run** in this work - no tool can run workflow tests from a session.

Full detail: each `EPIC-COP-*.md` has "Test results" and "Not proven" sections; the tracker has the
decisions waiting. `FABLE-REVIEW-PROMPT.md` lists every live object made or changed, with ids.

## 3. What the founder has approved, and what not

**Approved (2026-11-15, in chat):**
- Changing the **live planner endpoints** needed for the two server-side rules in section 4-A,
  **one at a time, each tested in the test account before the next**, and only **after the review
  session has finished**.
- Deleting your own scratch functions and test-account fixtures (standing OK, see memory).
- Running `tsc`, tests and git without asking.

**NOT approved - ask first, one short question each:**
- Any new table (COP-6 needs at least three). Any change to an existing table.
- Where outside logins are stored (COP-6 story 02). Do not design around a guess.
- Switching the six live planner endpoints to `planner_ops/*` (a separate, older decision - see 4-C).
- Any change to a live endpoint that is not part of 4-A.
- Editing `CLAUDE.md` or USR-3 (the founder has additions waiting; do not make them unasked).
- Pushing to GitHub. Any outward-facing action.

## 4. The work, in order

### 4-A. Two server-side rules (approved - live endpoints, one at a time)

**Rule 1 - Publish to live stays with a person (COP-5 story 02).**
- Today it holds only because the copilot has no publish tool and no login. The story wants the
  refusal in the publish endpoint itself.
- Endpoint: planner `562` (Publish to live). Add, right after the caller is known: if the caller is
  an AI identity (`copilot/identity_for_user` → `is_ai`), refuse. Use the existing person-only code
  the approval gate uses for "Publish a plan to live" (read `functions/copilot/action_gate.xs` for
  the code and wording - one code, one message; the guard test will fail on a second wording).
- Also look at bulk publish and republish endpoints in the planner group - same rule, same function.
  Put the check in ONE shared function and call it from each; do not copy it.
- Test: there is no way to sign in as the copilot over HTTP, so prove it with a scratch function
  that calls the shared check for user 26 (refused) and user 22 (allowed), then prove the screen
  path still publishes a draft day as user 22. Log a `rejected` event on refusal.

**Rule 2 - A switched-off copilot is not given new work (COP-5 story 06).**
- Today the rule is in the planner screen only (`webapp/protype-2/src/planner/aiAgentModel.ts`,
  12 handlers in `PlannerApp.tsx`).
- Server rule: a plan column (`planner_agent`) whose `user_id` is an AI identity that is switched off
  (`user_status.is_active == false`) cannot be the target of: starting a day (538), scheduling a step
  (560), scheduling a card (583), placing or creating a task onto its day, moving a day to it, or an
  assignee override naming it. One shared function, e.g. `planner_ops/assert_agent_assignable
  {agent_id}`, that never throws for a person or an unlinked AI column.
- New error code needed (next free: **E-COP-058**). Add it to
  `webapp/protype-2/src/ops/errorCatalog.json`; use the same sentence as `COPILOT_OFF_MESSAGE` in
  `aiAgentModel.ts` so screen and server say the same thing.
- Also call it from `planner_ops/create_timeline` and `planner_ops/schedule_work_task` so the
  copilot's own tools obey it.
- Test in account 13: switch the test copilot off (section 7), try each path against plan person 55
  (plan 46) or 52 (plan 44) → refused with the code; a person column still works; switch it back on.

**How to change a live endpoint safely (every time):**
1. `getAPI` with `include_xanoscript: true` → diff against the repo file. If they differ, stop and
   say so - do not overwrite live with a stale file.
2. Make the smallest additive edit. Keep `exclude_middleware = true` wherever raw input is read.
3. Push ONE endpoint. Smoke-test it over real HTTP as the test admin: the new refusal, AND the
   normal success path, AND one PATCH that omits optional fields (they must not be blanked).
4. Rollback is the previous source you fetched in step 1 - keep it in the scratchpad until tested.
5. Only then the next endpoint. Record each in the epic's Test results.

### 4-B. Four planner tools (COP-5 story 01, no approval needed - all new objects)
Time window (endpoint 613), start time (617), unschedule, schedule a whole card (583).
- Pattern is already built six times: copy the endpoint's rule into `functions/planner_ops/<name>.xs`,
  then a thin tool `ai/tool/plan_<name>.xs` that does gate → pin required (E-COP-045) → Planner grant
  (`usr/assert_module_access`) → `copilot/plan_in_business` (E-COP-038) → live day refused
  (E-COP-055) → the shared function. Read `ai/tool/plan_schedule_step.xs` as the model.
- Unschedule is allowed on **draft days only** (epic governance).
- Then add each tool to agent 40 (`ai/agent/emgram_copilot.xs`: the tools list and the "Drafting a
  plan" section). The agent already has 33 tools; keep the prompt short.
- Prove each with `debugTool` (section 7) and extend `tests/cop5_tool_vs_endpoint.py` with the same
  bad input through the live endpoint - the answers must match.
- **Not in scope without asking:** live-day changes "through approval" instead of refusal. That needs
  a design decision (which action type, what the owner sees).
- Be honest in the epic: each of these is one more rule that exists twice until 4-C.

### 4-C. Switching the six live endpoints to `planner_ops/*` (NOT approved - ask)
523, 535, 538, 554, 560, 570 still hold their own copy of rules that also live in
`functions/planner_ops/`. Conditions from the first Fable review are in the tracker ("The plan to
move planner rules - verdict: yes, if"). If the founder says yes: one endpoint at a time, replay the
same inputs before and after, compare rows and events written, not only the answers. The builder
found real bugs in the live endpoints while copying (listed in EPIC-COP-5 "Found in the live
endpoints") - decide per bug whether the shared function keeps or fixes it, and say so.

### 4-D. Click through what was never clicked (no approval needed)
In the browser, on the test account, plan 46:
- Edit an AI column → the "Who does this work? - The account copilot" checkbox: tick, save, reload,
  still ticked; untick, save, reload, unlinked. A **person** column still saves its login.
- Copilot switched off → drop a job card, "Place…", start a day, drag a task onto its column: each
  refused with the message. Switched on → each works.
- Plan Health tile: people's open capacity, with the "AI:" line under it.
- The copilot panel's "Scheduled runs" list and Details.
The preview pane would not take clicks last time while hidden - ask the founder to bring the Browser
pane forward, or use `read_page` / `find` and `javascript_tool` for inspection only.

### 4-E. The weak spot: the AI marking work done that it did not do
First scheduled run completed a delivery task with no tool call. Fixed by instruction only in the
run prompt (`functions/copilot/run_for_business.xs`, `$ask`), re-tested once. Chat still has the
softer wording (agent 40, "Your own tasks"). Options to put to the founder (do not build unasked):
tighten the chat prompt the same way (cheap); or a server rule in `record_my_task_event` - an AI may
not record `completed` on a task unless it made at least one allowed write tool call since it
started the task (uses `tool_call_log`). The second is the real fix.

### 4-F. Smaller follow-ups (do when nearby)
- Prune old `copilot_run` rows (24 a day per switched-on business; `nothing_to_do` rows are most of it).
- `get_map_learnings` ignores `is_outlier`; only the "shorter" direction was proven.
- `copilot/plan_in_business` returns `name` when the plan is not found.
- The copilot once said "8-9 minutes" for a figure of about 505 minutes: tools return bare
  `..._minutes` numbers. Consider returning a ready-made phrase.
- Catalog endpoints 594 and 599 still use `exclude_middleware = false` (no middleware on that group
  today - they break the day one is attached).
- COP-4 story 05 "my edits teach it" - nothing records how the owner edits the copilot's drafts.

## 5. COP-6 (connections library) - needs the founder before any build

Read `EPIC-COP-6-connections-library.md`. Nothing exists yet. To start it you need answers to:
1. May three new tables be added? (a) the library of available connections per account, (b) a switch
   per business per connection with "last worked" time, (c) a write-only store for a login.
2. **Where is a login kept?** It must never be returned by any screen, endpoint or tool, never be
   logged, and be attached to the outgoing request by the server. Options to explain in plain words:
   an encrypted column in Xano with the key in an environment variable, versus an outside secret
   store. This is the risky story (02) - Opus 5.5 / Fable 5.2 only, review pass after.
3. What is the first real connection (story 05)? The epic says a rental-booking system for the
   illustration business - an illustration, not a requirement. Ask.
Until then you can only write table definition files and a design note. Do not push them.

## 6. What to keep a pulse on

| Watch | Why | How to check |
|---|---|---|
| Task 21 `copilot_scheduled_run` (hourly, active) | An AI that acts with nobody watching | `getTaskRequestHistory` task 21; table 155 rows; `event_log` feature `COP-5` step `run_tick`. One tick event per hour, always. A task that "runs" and writes nothing is the heartbeat incident again |
| `copilot_run` (table 155) | Grows hourly; failed rows mean a run died | Any `status = failed`, or a `running` row older than 30 minutes |
| Test account 13, business 49 | **Scheduled work is ON** (level `scheduled_work = tell`) - one row an hour | Switch it off on the Approvals screen when testing is over (the founder has not said to yet) |
| Test copilot (user 26) | Probes switch it off and on | `user_status.is_active` must be **true** when you finish. Check before you end a session |
| Rules that exist twice | Six planner rules (ten after 4-B) live in an endpoint AND in `planner_ops/*` | `tests/cop5_tool_vs_endpoint.py`; change both sides or neither |
| Live vs repo drift | Helper sessions pushed several objects verbatim; nobody diffed them back | Before editing any live object, fetch it and diff. The review's drift report says where things stand |
| The 31 endpoints of the flag fix | Proven on 2 of 31 | Any report of a field going blank after a save in the planner or the map editor |
| Health page | Run failures and refusals surface there | `COP-5 run_failed`, code `E-COP-057` |
| AI cost | Each real run and each chat turn calls the model | Runs only call the AI when the copilot's open tasks changed; chat probes cost a call each |

## 7. How to work here (things that are not in CLAUDE.md yet)

**Testing**
- HTTP as the test admin: `product/stories/Epic-23/tests/cop5_lib.py` (`token`, `req`, `check`,
  `done`). The session is cached in the temp dir; run a probe with `-` to reuse it. If it has
  expired: run `Getting Started Template/generate_magic_link` for user 22 with `runWorkspaceFunction`
  and pass the token as the first argument once. **Never print a token or a ticket.**
- Tools cannot be called over HTTP. Run one for real with `debugTool` (it writes). It needs a
  ticket: `runWorkspaceFunction usr/mint_tool_ticket {user_id: 26, journey_map_id: 0,
  journey_architecture_id: 49, source: "copilot_chat", ttl_seconds: 1200}`. `debugTool` hides the
  message of "access denied" and "not found"; input errors show their text.
- Functions: `runWorkspaceFunction`. Flip state in the test account with a throwaway
  `scratch/...` function using `db.patch` (never `updateTableContentItem`), and delete it after.
- The real AI in chat: `tests/cop5_chat_probe.py`, `tests/cop4_learn_chat_probe.py` (each costs calls).
- Every probe in `tests/` writes data. None is a read-only check.

**Pushing**
- Fetch live first, diff, then push. A clean push only proves it parses - smoke-test after.
- Long files: a helper session can push a file verbatim (brief it: only that call, no fixes, report
  the exact error). It costs about 100k tokens each time; pasting the file yourself is cheaper for
  short ones.
- The file name's number is the live id (`655_copilot_runs_GET.xs`); rename after creating.

**Guard tests that will catch you (run `npm test` before committing)**
- Every error code in a `.xs` file must be in `errorCatalog.json`, and **one code = one message**
  (the literal text in the file must equal the catalog's `user_message`).
- A new table must be in `schemaAudit.ts`'s manifest and, if it is history, in `historyTables.ts`.
- A new test file must be added to the `test` script in `webapp/protype-2/package.json`
  (`node:test` + `node:assert/strict`, not vitest).

**Engine facts learned this session** (the founder has not yet approved adding them to CLAUDE.md)
- `util.get_raw_input` must use `exclude_middleware = true`. With `false`, behind any pre-middleware,
  every declared input comes back and "was this field sent?" is always yes.
- `$list|slice:0:N` works on a plain query list. A paged query result exposes no keys.
- A `|` inside a regex pattern literal works (CLAUDE.md's pipe-in-a-string note is narrower than written).
- `account_feature_flag.flag_key` is an enum - a new flag is a change to an existing table.
- A unique-index violation in a `db.add` inside `try_catch` is caught cleanly and uses up an id.
- `security.create_uuid as $x` works. `$x|substr:0:N` works.
- Keep per-item logic that needs an `if` in its own function and call it from the loop with
  `function.run` - that is how the scheduled run avoids the "conditional inside foreach" trap.

**Shell**
- The Bash tool breaks on an apostrophe inside a heredoc. Write scripts with the Write tool into
  the scratchpad and run them. Python edits: assert each anchor occurs exactly once before replacing.

**Git**
- Stage files by name. Never commit `product/learning-fixes.md`, `.obsidian/`, the frontend zip,
  loose images/screenshots, `product/prototype/`, `product/updates/`.
- End commit messages with the attribution line the session gives you.

## 8. Ids you will need

- Workspace 1. API groups: journey-map id 4 (`/api:ER4MRRWZ`), planner id 24 (`/api:PE5iDldw`),
  auth `/api:RPonubWS`, members `/api:Fcgmwc6Y`.
- Test account 13: admin user 22 (`usr2-q@example.com`), copilot user 26, business 49 (other
  business 48), map 261 (version 28), plans 44, 45, 46, jobs 143-146, tasks 865-872, plan people
  51-55 (52 and 55 are AI, linked to user 26), days 53-54 published (2026-11-15), 55-56 draft.
- Agent 40 `Emgram Copilot`, agent 41 researcher. Gate: function 311. Task 21. Table 155.
- Next free error code: **E-COP-058**.
- Full list of objects and ids: `FABLE-REVIEW-PROMPT.md`, section 3.

## 9. How to report to the founder

Non-engineer, only support person. **At most 5 short bullets, one line each, plain words, no
paragraphs, no tables unless asked, one question max and last.** Say what was built, which tests
pass or fail, what differs from the epic and why, and what is next. State plainly what was not
proven. Record results in the epic's Test results section, and keep the tracker's "Where things
stand" current. Stop and ask before anything in "NOT approved" above.
