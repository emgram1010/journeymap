# EPIC-USR-3 — Only real, permitted people do the work

**Epic:** Epic-13 — Who is in the account, and what they can reach
**Status:** 📋 Not started
**Model:** **Opus 5.5.** Same reasoning as USR-2: this is a guards epic, it
sits on the write path of the Planner and Execution, and a mistake here either
blocks real work or waves it through. Run an Opus review pass after it.
**Depends on:** USR-2, completely. Every rule in this epic asks "does this
person hold this grant?", and there are no grants until USR-2 ships.

---

## Why

USR-2 answers *"may this signed-in user enter this module?"* It asks the
question about the **caller**.

This epic asks it about the **subject** — the person a plan is handing work to.
Those are not the same person, and nothing today checks the second one at all:

- A plan can name `Dana Person` as an agent with **no login whatsoever**, and
  schedule a week of her work.
- A task can be assigned to a person-agent whose user was switched off
  yesterday.
- A task can be assigned to someone who, after USR-2, cannot even open the
  Execution module to see it.

In every case the plan looks complete, the Gantt fills in, and the work is
assigned to nobody who can actually do it. That failure is silent and it is
discovered late — at the moment someone expects the work to be done.

The founder's words, 2026-10-22:

> What about enforcing that any user using the intelligence layer, being an
> agent, that's assigned plan tasks or that execute tasks in the execution
> layer, must have a user account and must be assigned planning and execution
> permissions.

And, clarifying immediately after:

> When I mean an agent, I mean a person, not an AI agent.

## The rule

> **A person doing work in this product is a user account with a grant.**
> No login, no work. No grant, no work.
> An **AI** agent is not a person, holds no grant, and is out of scope.

Three layers of question, now all answered:

| Question | Who answers it |
|---|---|
| May **I** enter this module? | USR-2's middleware, on the caller |
| May **this person** be given work in it? | **USR-3**, on the subject |
| Whose things may I touch once inside? | GOV-1 / SEC-1 tenancy, unchanged |

## What is already true, verified live 2026-10-22

Checked against workspace 1 before a line of this was written.

| Fact | Detail |
|---|---|
| `planner_agent.kind` | An enum of exactly `person` \| `ai`. The person/AI split this epic needs **already exists** |
| `planner_agent.user_id` | **Already exists**, FK to `user`, and is **never required** |
| `agent_profile.user_id` | Same, with `0` documented in the table header as "an AI profile with no login" |
| `planner_task.assignee_agent_id` | FK to `planner_agent`, btree indexed. This is where work meets a person |
| `activity_log.performer_user_id` | FK to `user`, described as "Who did it, when a person did. 0 for system or AI" |
| `planner/resolve_actor` | The first call in every planner endpoint. The chokepoint for caller checks already exists and is not being replaced |

**So this epic adds no column and no table.** It makes an existing, optional,
widely-ignored link **required at the moment work is handed over** — which is
why it is small, and also why it is risky.

### 🔴 The live numbers, and the reason this cannot simply be switched on

| Count | Value |
|---|---|
| `planner_agent` rows | **35** |
| of which `kind = "ai"` | **15** — all with `user_id = 0`, correctly, forever |
| of which `kind = "person"` | **20** |
| person-agents **with** a linked user | **7** (users 2, 9) |
| 🔴 person-agents with **no** linked user | **13** |

Thirteen is 65% of the person-agents in the product. Most are old test
fixtures (`C1`–`C4`, `Explicit`, `Sibling Agent`, `Cascade A Renamed`), but they
sit in real `planner_workspace` rows, and a validate-everything-on-read rule
would break plans the founder still opens.

## The grandfathering decision

**Enforce on write, never on read.** A row that already exists is never
re-validated; only a new or changed assignment has to pass.

This was chosen over the "grandfather flag" first sketched in conversation,
because it needs no flag, no column, no backfill and no migration — and because
the flag version has a failure mode this one does not: a flag that defaults
wrong, or is never cleared, silently becomes permanent.

| Action | After this epic |
|---|---|
| Opening a plan that contains an unlinked person-agent | Works, exactly as today |
| Viewing a task already assigned to an unlinked person-agent | Works |
| **Assigning** a task to an unlinked person-agent | 🔴 Refused |
| **Adding** a new person-agent with no user | 🔴 Refused |
| **Re-saving** an existing unlinked person-agent unchanged | Works — see story 04's counter-measures |
| Recording execution as an ungranted user | 🔴 Refused |

The thirteen are then **listed on the Health page** rather than left to be
discovered, and an admin can link each one to a real user or leave it alone.
Nothing expires and nothing is deleted.

## Error codes

| Code | Means | HTTP |
|---|---|---|
| `E-USR-016` | This person has no user account yet — link them to one first | 400 |
| `E-USR-017` | That person has not been given access to this module | 403 |
| `E-USR-018` | Only someone with Execution access can record work as done | 403 |
| `E-USR-019` | That login belongs to another account | 403 |

`E-USR-005` (account switched off) and `E-USR-006` (you do not have access to
this module) are **reused unchanged**. The distinction that matters:

> `E-USR-006` is *"**you** cannot go there."*
> `E-USR-017` is *"**they** cannot go there."*

Two different sentences to two different readers. One code could not carry
both, and the registry test (`errorCodeRegistry.test.ts`) would catch the
attempt — it already caught exactly this during USR-1, when a delete reused
`E-USR-004` for a second meaning and `E-USR-015` had to be minted.

---

## Stories

### US-USR-3-01 — A person-agent is a real user

**As the** founder
**I want** a person in a plan to be an actual user account
**So that** work is never assigned to a name that cannot sign in.

```gherkin
Scenario: Adding a person-agent requires a login
  Given I am building a plan
  When I add a person-agent with no linked user
  Then it is refused with E-USR-016
  And the refusal names the person and tells me to add them on the Team page

Scenario: Adding a person-agent with a login succeeds
  When I link them to a user in my account
  Then the agent is created as before

Scenario: An AI agent needs no login
  When I add an agent of kind "ai"
  Then no user is required and nothing is refused

Scenario: Someone else's login cannot be used
  When I link a user from another account
  Then it is refused with E-USR-019, which does not confirm they exist

Scenario: A switched-off user cannot be added as an agent
  Given a user deactivated in USR-1
  Then it is refused with E-USR-005

Scenario: The same person is not two agents in one plan
  Then the second one is refused, as PLN-5 already does
```

**Method:** extend `planner/assert_agent` and the `agent_profile` create and
edit paths. The check is one shared function — `usr/assert_person_is_user` —
not a copy in each.

**Counter-measures:**
- 🔴 **One rule, one function.** The LOG-1 lesson: a rule copied into the
  creator, the editor and the importer will eventually disagree with itself and
  all three will sound equally certain. `planner_agent` and `agent_profile`
  both go through the same function.
- 🔴 **`user_id = 0` is the "no login" sentinel in both tables**, and both table
  headers say so. Test `!= 0`, never `!= null` — `0 == null` is `true` in this
  engine (`CLAUDE.md`, VAR-1), so a null test passes for the exact case it is
  meant to catch.
- An omitted optional `int` input arrives as `0`, indistinguishable from a
  deliberate 0 (`CLAUDE.md`, VAL-1). "Did the caller send a user?" needs
  `util.get_raw_input` and `|has:"user_id"`, not a falsy test.
- Tenancy for a person profile is read through `user.account_id`, not stored —
  `assert_agent_profile`'s own header documents this. Do not add a second,
  drifting copy of the account on the agent.

**Done when:** a new person-agent cannot be created without a same-account,
active user behind it, and an AI agent is created exactly as it is today.

---

### US-USR-3-02 — Work is only assigned to someone who can reach it

**As a** planner
**I want** assignment to refuse people who cannot open the module
**So that** a full-looking plan is a real one.

```gherkin
Scenario: Assigning to a granted person
  Given a person-agent whose user holds Execution
  When I assign them a task
  Then it is assigned as before

Scenario: Assigning to an ungranted person
  Given their user does not hold Execution
  Then it is refused with E-USR-017
  And the message names the person and the missing module

Scenario: Assigning to an unlinked person-agent
  Given a legacy person-agent with no user
  Then it is refused with E-USR-016

Scenario: Assigning to an AI agent
  Then nothing is checked and it behaves as today

Scenario: Unassigning is always allowed
  When I clear an assignee
  Then it succeeds even if that person is ungranted or switched off

Scenario: Revoking a grant does not rewrite existing plans
  Given a person with tasks assigned
  When their Execution grant is revoked
  Then the existing assignments stay, and new ones are refused
  And the Health page shows those tasks need a new owner
```

**Method:** one guard on every write that sets `planner_task.assignee_agent_id`
— `place_task`, `derive_tasks`, the bulk assignment paths and the AI tool that
scaffolds a plan.

**Counter-measures:**
- 🔴 **Enumerate every write path to `assignee_agent_id` in a table in this
  file before writing code.** A missed path is an open door that looks shut —
  the same failure shape that made USR-2 choose middleware over ~150 hand
  edits. `grep assignee_agent_id` across `apis/`, `functions/` and `ai/` is the
  starting point, not the finish.
- 🔴 **Unassigning must never be blocked.** If revoking a grant made the
  resulting tasks unmovable, the only way to fix a plan would be to re-grant
  the person — a lock with its key inside.
- 🔴 **Which grant is required is a real decision, written down in Decided
  below**, not assumed: being *given* work requires **Execution**, because that
  is the module where work is done. The Planner grant is about who may *build*
  the plan, and USR-2's middleware already checks that on the caller.
- Bulk assignment means a transaction: all, or none. A half-assigned plan is
  worse than a refused one (`CLAUDE.md` — `db.patch` by `field_name` touches
  only the FIRST match).
- The AI scaffolding tool writes assignments too. A guard the humans pass and
  the agent bypasses is not a guard.

**Done when:** every path that can set an assignee runs the same check, the
paths are listed in this file, and a task cannot be handed to someone who
cannot open Execution.

---

### US-USR-3-03 — Only a granted person records work as done

**As the** founder
**I want** the person completing a step to hold Execution at that moment
**So that** the record of who did what is a record of someone who could.

```gherkin
Scenario: A granted performer
  Given I hold Execution
  When I mark a step done
  Then it is recorded with my user id, as today

Scenario: An ungranted performer
  Given my Execution grant was revoked after I opened the page
  When I mark a step done
  Then it is refused with E-USR-018, not silently accepted

Scenario: A switched-off user cannot record work
  Then it is refused with E-USR-005

Scenario: System and AI entries are unaffected
  Given performer_user_id = 0, the documented system/AI value
  Then nothing is checked and the entry is written

Scenario: The refusal does not lose the performer's typing
  Then whatever they entered is still on screen
```

**Method:** the check belongs in the perform write path, next to the existing
status-transition rules — **not** only in USR-2's middleware. The middleware
answers "may you be here"; this answers "may you be the name on this record",
and a token issued before a revoke still passes the first question.

**Counter-measures:**
- 🔴 **This is the open-session hole USR-1 left open**, recorded in its Still
  open section: a revoked or deactivated user keeps working until their token
  expires. USR-2's middleware closes it for *entering*; this story closes it
  for *writing*.
- 🔴 **`performer_user_id = 0` means system or AI** and must stay unchecked, or
  every automated transition in the product starts failing. The table header
  documents the 0; this story must branch on it explicitly.
- Keep the user's typing on a rejected save — the standing frontend rule.
- The status engine (LOG-1) is not touched. A permission refusal happens
  **before** `log/next_status` is consulted, so no transition is half-applied.

**Done when:** a user whose Execution grant was revoked mid-session is refused
when they try to record a step, with a sentence rather than a code, and system
entries are unaffected.

---

### US-USR-3-04 — The thirteen are visible, not buried

**As the** founder and only support person
**I want** the existing unlinked person-agents listed and fixable
**So that** grandfathering is a transition, not a permanent exception.

```gherkin
Scenario: The Health page lists them
  Then every person-agent with no linked user is shown, with its plan

Scenario: An admin links one to a user
  When I pick a user from my account
  Then the agent is linked, and new assignments to it are allowed

Scenario: Nothing expires
  Then an unlinked agent is never deleted, hidden or deactivated by this epic

Scenario: Re-saving an untouched legacy agent still works
  Given an unlinked person-agent
  When a plan edit re-saves it without changing its user
  Then it is not refused

Scenario: Tasks whose owner lost access are listed too
  Then each is shown with the person and the missing module
```

**Method:** a read-only count on the existing Health page, from one
`return = {type: "count"}` query per issue, plus a small link action reusing
story 01's guard.

**Counter-measures:**
- 🔴 **"Re-saving unchanged must not be refused" is the subtle one.** A guard
  written as "every person-agent in this write must have a user" breaks every
  edit to an old plan. The check must fire on the **assignee or user actually
  being set**, not on the row being touched. Story 01's and 02's tests both
  carry this case, and it is the one most likely to be got wrong.
- Count queries only. The Health page must not load every agent row to count
  them (`CLAUDE.md`: `return = {type: "count"}` returns a plain int).
- Do not offer a "link them all automatically" button. There is no rule that
  maps `C3` to a person; a guess here writes a wrong audit trail.

**Done when:** the Health page names every unlinked person-agent and every
task whose assignee lost access, and an admin can fix one in two clicks.

---

### US-USR-3-05 — The exemption is not a loophole

**As the** founder
**I want** the AI exemption to be impossible to abuse
**So that** "it is an AI agent" cannot become the way around every rule above.

```gherkin
Scenario: A person-agent cannot be relabelled as AI
  Given a person-agent with tasks assigned
  When someone changes its kind to "ai"
  Then it is refused

Scenario: An AI agent cannot be given a login
  When a user is linked to an agent of kind "ai"
  Then it is refused

Scenario: An AI agent cannot perform as a person
  Then performer_user_id stays 0 for every AI entry

Scenario: kind is required and validated
  When a new agent omits kind
  Then it is refused, not defaulted to "ai"
```

**Method:** two checks in the same shared function as story 01. `kind` is
already an enum of exactly the two values, so the allow-list is the schema.

**Counter-measures:**
- 🔴 **An omitted optional `enum` input arrives as `""`, not null, and `??`
  does not catch it** (`CLAUDE.md`). A missing `kind` must be an explicit
  refusal; defaulting it would default to the unchecked path, which is the
  worst possible direction to fail in.
- 🔴 **`model_id` only applies to `kind = "ai"`**, a rule `planner_agent`'s own
  header says the schema does not enforce and PLN-5 does. Do not duplicate it
  here; extend the existing check if it needs extending.
- A relabel is an edit, so it goes through the same write path as a create and
  therefore the same function. That is the whole reason story 01 insists on one
  function rather than three copies.

**Done when:** there is no sequence of legal edits that turns a person's work
into AI work, or an AI agent into a login holder.

---

### US-USR-3-06 — Every refusal here is answerable

**As the** founder and only support person
**I want** each refusal recorded with enough to answer "why can't they?"
**So that** this epic does not generate support questions I cannot close.

```gherkin
Scenario: Refusals are logged
  Then each records the actor, the subject person, the module and the code

Scenario: A link is logged
  Then linking a legacy agent to a user records who did it and when

Scenario: No names in the metadata
  Then ids and module keys only — no names, no email addresses

Scenario: Logging never blocks a permitted action
  Then a failed event write does not turn an allowed assignment into a refusal

Scenario: The Health page shows a spike
  Then a burst of E-USR-016 or E-USR-017 is visible there
```

**Method:** the existing `ops/log_event` path, as USR-1's five endpoints use.
No second log, no new table.

**Counter-measures:**
- 🔴 **Ids and keys, never names or email addresses.** The argument for
  including a name here ("the admin needs to know who it was") is the same
  argument that produced four logging bugs on 2026-10-15 and was refused again
  in USR-1 story 08. The subject's id is enough; the Team page resolves it.
- Log refusals, not successful checks — USR-2's volume rule applies unchanged.
- 🔴 **`db.patch` on a `json` column merges rather than replaces**
  (`CLAUDE.md`). Any metadata correction is two patches: `null`, then the
  value.

**Done when:** every refusal in stories 01–05 appears in `event_log` with its
code, and no entry contains a person's name or email.

---

## MVP scope

**In:** all six stories, in order. 01 and 02 are the epic; 03 closes the
session hole; 04 is what makes 01 and 02 safe to turn on; 05 is what stops them
being bypassed; 06 is the standing governance requirement.

**The ordering rule:** story 04's Health-page list is built **before** stories
01 and 02 are enforced. Thirteen broken rows should be visible before they
start causing refusals, not after.

**Deferred:**
- Per-plan or per-task permissions. A grant is still module-wide.
- Requiring a login for an AI agent's *owner*. Worth doing; needs its own
  thinking about who owns an AI agent, which nothing records today.
- Automatically reassigning tasks when someone loses access. The Health page
  lists them; a human decides. Automatic reassignment writes a plan nobody
  agreed to.
- Expiring or cleaning up the thirteen legacy agents.

## Governance

| Area | What this epic does |
|---|---|
| Tenancy | Unchanged. A linked user must be in the same account (`E-USR-019`), which is tenancy being *checked*, not relaxed |
| Validation | `kind` validated against the existing enum; `user_id != 0` with the sentinel tested explicitly, never via `!= null`; module keys from USR-2's single allow-list |
| Error codes | `E-USR-016`–`E-USR-019` added to `src/ops/errorCatalog.json`. `E-USR-005` and `E-USR-006` reused unchanged, and `E-USR-017` is deliberately separate from `006` — "they cannot" is a different sentence to "you cannot" |
| Events | Every refusal logs `rejected` with the code; links log who and when; ids and keys only |
| Table constraints | **No new table and no new column.** An existing optional FK becomes required at write time |
| Delete behaviour | Nothing is deleted. No agent, task, plan or log entry is removed, hidden or deactivated by this epic |
| Rollback | Every check is a `precondition` in a shared function. Reverting the commit restores previous behaviour, and no data written under the rules becomes invalid |
| No silent failure | Refusals are real 4xx with a code and a sentence. The grandfathered rows are *listed*, not ignored |
| Testing | Unit tests for the client-side mirror; live exercise on a **test account** and a throwaway plan, never the founder's own plans and never map 178 |

## Test Results

_Not started._

| Story | Tests | Result |
|---|---|---|
| 01 | Person-agent with no user refused; with a user created; AI needs none; cross-account refused; deactivated refused; duplicate person refused | — |
| 02 | Granted assign; ungranted refused; unlinked refused; AI unaffected; unassign always allowed; revoke does not rewrite existing plans; every write path enumerated and covered | — |
| 03 | Granted performer records; revoked mid-session refused; switched-off refused; `performer_user_id = 0` unaffected; typing kept on refusal | — |
| 04 | Health page lists the 13; link action works; nothing expires; **re-saving an untouched legacy agent is not refused**; lost-access tasks listed | — |
| 05 | Person cannot be relabelled AI; AI cannot take a login; AI never performs as a person; missing `kind` refused | — |
| 06 | Refusal logged with code; link logged; no names in metadata; log failure does not block; Health page spike | — |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| 🔴 **A write path to `assignee_agent_id` is missed** | An unguarded path is an open door that looks shut, and there is no middleware equivalent for a write-path rule | Enumerate every path in this file before coding; `grep` across `apis/`, `functions/` and `ai/`; the AI scaffolding tool counts as a path |
| 🔴 **"Every person-agent must have a user" breaks editing old plans** | 13 of 20 person-agents would fail it, so routine edits to real plans start being refused | Enforce on the field being set, not on the row being touched; story 04's re-save test is the gate |
| 🔴 **The AI exemption becomes the bypass** | Every rule here is skipped for `kind = "ai"`, and `kind` is editable | Story 05; a missing `kind` is refused rather than defaulted |
| 🔴 **Blocking unassignment creates an unfixable plan** | Revoking someone's grant would freeze their tasks in place | Unassign is explicitly always allowed, with its own scenario |
| 🟡 **Which grant does being assigned work require?** | Guess wrong and either planners cannot staff plans, or performers cannot be staffed | Decided below: Execution. Recorded with reasoning so it can be revisited deliberately |
| 🟡 **A per-assignment grant lookup on the write path** | Another query on an already heavy endpoint, inside a transaction | One query per distinct agent, resolved before the transaction, never inside a loop |
| 🟡 **The thirteen are never fixed** | Grandfathering becomes permanent and the rule becomes a half-rule | They are counted on the Health page, where the founder will see them |
| 🟢 **Migration** | None. No schema change at all | Nothing to roll back but code |

## Decided

| Question | Decision | Date |
|---|---|---|
| Does this apply to AI agents? | **No.** The founder's own clarification: *"when I mean an agent, I mean a person, not an AI agent."* An AI agent has no login, holds no grant, and `kind = "ai"` skips every check here | 2026-10-22 |
| Enforce on everything, or only on new writes? | **Write-time only.** No flag, no backfill, no migration — and no flag that can default wrong or never be cleared. Existing rows are never re-validated | 2026-10-22 |
| Which grant does being **assigned** work require? | **Execution.** The founder said *"planning and execution"*; read strictly that would stop a performer being staffed unless they could also open the Planner. Being *given* work needs the module where work is done; **Planning** is for whoever *builds* the plan, and USR-2's middleware already checks that on the caller. Flagged to the founder when this file was written | 2026-10-22 |
| Is the Intelligence Layer part of this epic? | **No story needed.** "A user using the intelligence layer" is a question about the caller, which is exactly USR-2's middleware on the `journey_map` group. Adding a second check here would be a second copy of one rule | 2026-10-22 |
| A new code for "they cannot reach it", or reuse `E-USR-006`? | **New — `E-USR-017`.** One code means one thing. USR-1 already hit this exact wall and had to mint `E-USR-015`; the registry test catches it | 2026-10-22 |
| Automatically reassign tasks when someone loses access? | **No.** The Health page lists them and a human decides. Automatic reassignment writes a plan nobody agreed to | 2026-10-22 |

## Still open

- 🟡 **Does an AI agent need an owning user?** Today nothing records who owns an
  AI agent, so nothing can be checked. Probably worth a story of its own once
  module grants exist; deliberately not guessed here.
- 🟡 **`agent_profile` has no unique index on `user_id`** — by design, because
  an int column cannot hold a real null and every AI profile shares `0` (the
  table header documents this). Once story 01 requires a real user for person
  profiles, a **partial** unique index on person profiles becomes possible.
  Unknown whether this Xano plan supports a partial index; not required by any
  story here.
- 🟡 **Does a person-agent need the grant for the module its plan belongs to**,
  rather than Execution specifically, once plans can span modules? Not a
  question today — plans live in the Planner — but it is the shape the
  "more granular in the future" request will arrive in.
