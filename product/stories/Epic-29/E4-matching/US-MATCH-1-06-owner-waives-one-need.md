# US-MATCH-1-06 — The owner waives one hard need for one job

**Epic:** MATCH-1 · **Size:** M · **Model:** **Opus 5.5** · **Status:** 🔴 **Not approved. Needs the founder's answer to D-10 before it is built.**
**Depends on:** stories 01, 03, 04

## Description

The founder decided (D-3): a planner cannot override a hard need; only the owner can relax the
rule to soft.

Reading the code turned up a consequence. A need is frozen into the published map version, and a
job reads the version it is pinned to. So when the owner changes "hard" to "soft" on the map and
publishes a new version, **new** jobs get the relaxed rule. The job that is stuck today keeps the
hard one. The only ways out would be to cancel the job and add it again, or to wait.

That turns "only the owner can relax it" into "nobody can relax it for the work that needs it
now".

**Proposed (builder's pick):** the owner, and only the owner, may waive **one** hard need for
**one** job, with a written reason. It is recorded, shown wherever the job is shown, and counted
on the Health page. The map is not changed. A planner still cannot do it, so D-3 holds.

**If the founder says no:** this story is not built, and story 05 offers "cancel and re-add on
the new version" as the fix instead.

## User story

**As** the owner, **I want** to let one job go ahead without a hard need when I judge it right,
**so that** urgent work is not stuck behind a rule I am allowed to relax.

## Acceptance criteria

```gherkin
Scenario: waive a need
  Given a job has a step with a hard need nobody can meet
  When the owner waives that need for the job, with a reason
  Then for that job the need is treated as soft: it warns and ranks, and no longer refuses

Scenario: a reason is required
  When the reason is empty or shorter than 10 characters
  Then it is refused, and what was typed is kept

Scenario: only the owner
  When an admin, a planner or an AI tries
  Then it is refused, and the attempt is recorded

Scenario: one need, one job
  Then other needs on the job, and the same need on other jobs, still refuse

Scenario: it is visible
  Then the job, its slots, the publish preview and the frozen day all show "<need> waived by <owner>: <reason>"

Scenario: the performer sees it
  Then the person doing the work sees that the need was waived for this job

Scenario: withdraw a waiver
  Given the work has not been published to live
  When the owner withdraws it
  Then the need refuses again, and any assignment that no longer fits is marked for review

Scenario: withdraw after the day is live
  Then the live day is not changed, and the owner is told so

Scenario: availability cannot be waived
  Then a waiver never lets work go to someone who is off that day

Scenario: a soft need
  Then there is nothing to waive, and the action is not offered

Scenario: a cancelled or finished job
  Then a waiver cannot be added

Scenario: counted
  Then the Health page shows waivers per month, by requirement

Scenario: another account
  Then it cannot see or add waivers on my jobs
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A waiver becomes the normal way to work and the hard need means nothing | Owner only, reason required, shown on the work, counted on the Health page. A requirement waived often is shown to the owner as "consider making this soft" |
| A waiver is used for something the law requires | The system cannot know. The waiver screen says plainly that the owner is taking responsibility, and the record names them |
| An AI or an admin grants a waiver | The endpoint checks the caller's rank (`usr/account_rank`) and refuses an AI (`copilot/assert_person_only`). No tool exists |
| A waiver leaks to another job through a repeat | Waivers are a fact about one job. A repeat never copies them (REPEAT-1 story 03) |
| Two requests add the same waiver | Unique index on (job, requirement) |
| The rule is read in a second place to apply waivers | `match/check` takes waivers as one of its facts; nothing else interprets them |
| Withdrawing silently strands assigned work | It marks the affected work for review and says how many items |
| The frozen day does not show the waiver, so there is no record of what was promised | The publish snapshot records it (story 04's new canonical version) |
| The owner is unreachable | An account has one owner today (`account_owner`). Platform support does **not** waive on their behalf. See below |

## Governance

- **Errors (suggested):** `E-MATCH-030` only the owner can waive a need · `E-MATCH-031` give a reason (at least 10 characters) · `E-MATCH-032` this job is finished or cancelled · `E-MATCH-033` this need is not hard for this job.
- **Events:** `matching.need_waived`, `.waiver_withdrawn` (job, requirement, reason, owner). Refused attempts record a `rejected` event with who tried.
- **Delete behaviour:** a waiver is withdrawn, never deleted; the row keeps who and when.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-06-1 | Waived need warns and no longer refuses, on every path in story 03 |
| T-MATCH-06-2 | Other needs and other jobs still refuse |
| T-MATCH-06-3 | Admin, planner and AI refused and logged |
| T-MATCH-06-4 | Reason rules |
| T-MATCH-06-5 | Availability still refuses with a waiver in place |
| T-MATCH-06-6 | Shown on the job, the publish preview, the snapshot and the performer's view |
| T-MATCH-06-7 | Withdraw before live: refuses again, work marked. After live: day unchanged |
| T-MATCH-06-8 | A repeat does not copy a waiver |
| T-MATCH-06-9 | Two parallel waivers leave one |
| T-MATCH-06-10 | Second account refused |

## Keep a pulse on

- **Open:** what happens when the owner is away. A second person allowed to waive is a real need for a business that runs seven days. It is a permissions decision for the founder, not something to add quietly.
- If D-10 is refused, record that here and remove this story from the completion gate.
