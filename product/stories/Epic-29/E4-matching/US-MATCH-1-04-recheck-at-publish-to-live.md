# US-MATCH-1-04 — Recheck at Publish to live, and when things change

**Epic:** MATCH-1 · **Size:** M · **Model:** **Opus 5.5** · **Status:** 📋 Not built
**Depends on:** stories 01, 03; REPEAT-1 story 05 (the review mark)
**Touches:** Publish to live (LIVE-1, endpoint 562). Ask before pushing.

## Description

An assignment that was right on Friday can be wrong on Monday. A holding ran out. Someone was
recorded as away. The map was republished with a new hard need and a job was added on it.
Matching was switched on over a plan built before it existed.

Two things make that safe.

**Publish to live checks again.** It is the moment a plan becomes a promise to a person. Every
item on the day is run through the rule, and a hard mismatch or an unavailable person is a
blocker, listed with all the other blockers, the way Publish to live already works.

**Changes mark work for review.** When a holding ends or is removed, the work it affects is
marked "needs review" with the reason (the same mark REPEAT-1 and AVAIL-1 use). Nothing is moved
automatically, and a day already published is never changed.

## User story

**As** an owner, **I want** a day checked again at the moment it goes live,
**so that** no one is sent to do work they are not allowed or not there to do.

## Acceptance criteria

```gherkin
Scenario: publish a day with a hard mismatch
  Given an item on Ana's day needs something she does not hold
  When I preview or run Publish to live
  Then it is a blocker: the item, the need, and "move it or ask the owner"
  And it is listed together with every other blocker

Scenario: publish a day for someone who is off
  Then every item on the day is a blocker with AVAIL-1's reason

Scenario: soft mismatch or over hours
  Then they are shown as warnings and do not block

Scenario: a waived need
  Then it does not block, and the waiver is shown

Scenario: republish
  Then the same checks gate a republish

Scenario: the snapshot
  Then the frozen day records, per item, any warning or waiver that applied at publish

Scenario: a day already live
  When a holding ends or time off is recorded afterwards
  Then the published day is not changed
  And the planner sees a notice naming the day, the person and the reason

Scenario: a holding is removed or runs out
  Then future draft work it affects is marked "needs review: Ana's Forklift ended 31 March"

Scenario: holdings that run out by date
  When the daily check runs
  Then work on days after the end date is marked, without anyone editing anything

Scenario: matching is switched on over an existing plan
  Then existing assignments that no longer fit are marked for review; none is removed

Scenario: the cause goes away
  When the holding is recorded again
  Then the marks it raised are cleared

Scenario: show-only mode
  Then would-be blockers are shown as warnings and publishing is allowed

Scenario: matching is off
  Then Publish to live behaves exactly as it does today
```

## Counter-measures

| Risk | Prevention |
|---|---|
| The snapshot format changes and old hashes stop verifying | Warnings and waivers go in under a **new canonical version**, `publication|v4` (today is `v3`, which added start overrides, in `live/build_publication`, `live/canonical_items` and `live_add_attempt`; the 562 header comment still says v2 and is stale), with a fallback for older publications. All three builders, and the TypeScript twin, move to v4 together. Every existing publication is verified before and after on a clone |
| A new blocker is returned alone and hides the others | Added to the existing blocker list; a test asserts a day with three kinds of blocker returns all three |
| The publish check uses a different rule from the save | Both call `match/check` |
| The daily check fails silently | It writes a heartbeat every run; the Health page shows the last run. No filter function inside a `where` clause; bounds computed into variables first |
| The daily check marks the same work every night | One mark per slot; a re-run adds nothing |
| A published or started day is touched | The search skips published days; a test compares publication hashes |
| Marks pile up and are ignored | They appear at the publish step as blockers (hard) or counts (soft), which is where they matter |
| Publishing clears a mark for a hard mismatch (REPEAT-1 D-8) | It cannot: a hard mismatch blocks publishing, so only soft and "copied" marks are cleared by publishing |
| Monday morning: a blocker with nobody able to fix it | The blocker names the fix (move it, or the owner waives it); the "work nobody can take" list (story 05) shows it ahead of time |
| An AI publishes around the check | Publish to live already refuses an AI |

## Governance

- **Errors (suggested):** blockers `E-MATCH-020` (hard need not held at publish) and `E-MATCH-021` (person not available at publish), each with item, person and reason.
- **Events:** Publish to live's existing events gain matching counts. `matching.work_marked` (cause, count). The daily check records a heartbeat and a summary.
- **Health page:** live days with a problem that arose after publishing; last run of the daily check.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-04-1 | Publish blocked by a hard mismatch; listed with other blockers |
| T-MATCH-04-2 | Publish blocked for a person who is off |
| T-MATCH-04-3 | Soft and hours warnings do not block |
| T-MATCH-04-4 | Republish gated the same way |
| T-MATCH-04-5 | Snapshot hash: new canonical version matches the TypeScript twin; old publications still verify |
| T-MATCH-04-6 | Holding removed: draft work marked; published day unchanged |
| T-MATCH-04-7 | Daily check: marks by date, heartbeat written, re-run adds nothing |
| T-MATCH-04-8 | Switch on over an existing plan: marks, no removals |
| T-MATCH-04-9 | Cause removed: only its marks cleared |
| T-MATCH-04-10 | Off and show-only modes |

## Keep a pulse on

- A problem on a day that is **already live and started** is only a notice. What the planner should do then (send someone else, record an exception) is the existing exception flow (EXC-1), not a new one.
