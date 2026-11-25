# MATCH-1 — Suggest, refuse, and recheck at Publish to live

**Epic ID:** MATCH-1 (E4 in this folder)
**Status:** 📋 Not built (docs only, 2026-11-25)
**Size:** L
**Model:** **Opus 5.5**, then an Opus review. This is a guard on every path that assigns work, and on Publish to live.
**Depends on:** REQ-1 (all), AVAIL-1 (stories 01–03), REPEAT-1 (story 05 for the review mark; story 04 for the open hook).
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** the system now knows what a step needs, what each person holds and when they work
(REQ-1, AVAIL-1). It still lets a planner give the work to anyone.

**Win:** for any piece of work on any day the system answers **who fits**. It suggests the best
person, refuses a hard mismatch, never gives work to someone who is off, and checks again at the
moment a day is published to live.

Founder decisions, 2026-11-25:
- **Hard** needs decide who is allowed. **Soft** needs only rank the people who are left (D-4).
- **Availability** applies to every piece of work (D-4).
- A planner **cannot** override a hard need. The work stays unassigned with the reason shown.
  Only the owner can relax the rule (D-3).

## 2. What exists today (repo and live compared 2026-11-25: planner code identical)

| Fact | Where |
|---|---|
| The planner assigns any active person. "Suggest by role" was deferred with ROLE-1 | SCHED-1 story 04, PRD PL-5, D-42 |
| One shared check already decides "may new work land on this person": matching extends it rather than guarding each caller (README F-8) | `functions/planner_ops/assert_agent_assignable`, called by 541, 542, 543, 545, 583, `schedule_work_task`, `schedule_card`, `create_timeline` |
| Paths that put work or a day on a person (README F-8) | `apis/planner/536, 538, 541, 542, 543, 545, 560, 583`; `planner_ops/schedule_work_task`, `schedule_card`, `create_timeline`, `live_add_attempt` (via 449, 450); `ai/tool/plan_schedule_step`, `plan_schedule_card`, `plan_start_day`. 544 cannot bring work in |
| Two gaps skip the shared check today (README F-16) | 542 with a day and no override; 541 when only the date changes |
| Outside orders are routed to a plan and a member by a routing table; same-day orders are added to a live day | DEMAND-1, tables 176–179 |
| Publish to live returns every blocker at once, and the same blockers gate a republish | `apis/planner/562_…publish_POST.xs` |
| A published day is a frozen snapshot with a hash; the performer reads only that | `static/tables/125_plan_publication.xs` |
| The feature-flag table's key is a fixed list | `static/tables/108_account_feature_flag.xs` |

## 3. Rule (the one rule)

For a person on a plan, a piece of work, and a date:

| Check | Result if it fails |
|---|---|
| The person is available that day (AVAIL-1) | **Refused** |
| The person holds every **hard** need on that date (REQ-1), unless the owner waived it for this job | **Refused** |
| The person holds every **soft** need | Allowed, with a **warning**, ranked lower |
| The person has enough hours left that day | Allowed, with a **warning**, ranked last (D-9) |

- Work with no needs and a person with nothing recorded pass every check. So nothing changes
  until someone records something.
- The answer always carries **every reason**, in plain words.
- This is one function (`match/check`) with one TypeScript twin. Everything calls it.

## 4. The switch

Matching is **off** per account until an admin turns it on. Three settings:

| Setting | Effect |
|---|---|
| Off | Today's behaviour. Nothing is checked |
| Show only | Suggestions and warnings are shown. Nothing is refused. Refusals that **would** happen are counted on the Health page |
| On | Hard needs and availability are enforced |

"Show only" is the dry run: the owner sees what would be refused before it is refused. The
switch lives in its own small settings table, because adding a key to the feature-flag table
means changing a table that would lose its text check. **Rollback is one setting.**

## 5. Do not break

- With the switch off, every endpoint in F-8 returns exactly what it returns today (checked before and after).
- A published day's snapshot and hash never change.
- A day that has been started is never touched.
- Publish to live still returns **all** blockers at once.
- An AI can never waive a need, switch matching off, or record that someone holds something.

## 6. Non-goals

- Assigning work automatically with no person involved. The system suggests; a person (or an AI drafting for a person) places.
- Rebalancing a whole plan in one click.
- Travel, location or equipment that is not a person.
- Fairness rules (spreading work evenly). Hours left is the only load signal.
- Overtime or pay rules.

## 7. New tables (additive)

| Table | What it holds | Guard |
|---|---|---|
| `account_matching_setting` | Account, setting (off, show only, on), changed by, changed when | Unique on account; no row = off |
| `work_item_need_waiver` | Job, requirement, reason, waived by, when, withdrawn when (story 06, pending D-10) | Unique (job, requirement) |

## 8. Stories

| File | Story |
|---|---|
| `US-MATCH-1-00-check-and-switch.md` | Read-only check of every assigning path; the off / show only / on switch |
| `US-MATCH-1-01-the-one-rule.md` | `match/check`: one function, one twin, golden cases |
| `US-MATCH-1-02-suggest-who.md` | A ranked list of who fits a piece of work |
| `US-MATCH-1-03-refuse-on-every-path.md` | Every way of assigning work goes through the rule |
| `US-MATCH-1-04-recheck-at-publish-to-live.md` | Publish to live rechecks; changes after assignment mark work for review |
| `US-MATCH-1-05-work-nobody-can-take.md` | One list of unassignable work, with the reason and what would fix it |
| `US-MATCH-1-06-owner-waives-one-need.md` | The owner waives one hard need for one job (pending D-10) |

## 9. Completion gate

- Switch off: all F-8 endpoints behave exactly as before.
- Show only: nothing refused; would-be refusals counted.
- On: a hard mismatch is refused on **each** path in F-8, with the same reason text.
- A person who is off that day is refused on each path.
- Soft mismatch and a full day are allowed with a warning.
- Suggestions are in a stable, explained order.
- Publish to live lists a hard mismatch with the other blockers; a republish is gated the same way.
- A holding that ended after assignment marks the work for review and never changes a published day.
- A repeat (REPEAT-1) sends work to the backlog when the copied person no longer fits.
- A same-day outside order that fits nobody is listed, not placed.
- The server and the TypeScript twin agree on every golden case.
- An AI caller cannot waive, switch or record. A second account sees nothing.
- Existing suites green. Test Results filled in. **Opus review done.**

## 10. Test Results

Not built. Nothing has been run.
