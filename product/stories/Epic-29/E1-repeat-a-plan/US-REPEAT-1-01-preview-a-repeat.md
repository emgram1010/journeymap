# US-REPEAT-1-01 — Preview a repeat

**Epic:** REPEAT-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 🟡 Server built and tested live 2026-11-25; screen not built
**Depends on:** story 00

## Description

A repeat writes a lot at once. Before it writes anything, the planner should see what the new
plan will hold and, more important, what it will **not**: a person who has since left, a job
that came from a customer order, a map that no longer has a published version.

The preview is also where the planner makes the few choices a repeat needs: the start date, the
name, and which jobs to leave out.

## User story

**As** a planner, **I want** to see what a repeat will copy and what it will leave out,
**so that** nothing in the new plan surprises me.

## Acceptance criteria

```gherkin
Scenario: open the preview
  Given a plan that runs 7 days
  When I choose "Repeat this plan"
  Then the start date offered is the day after the plan ends
  And the name offered is free in my account

Scenario: what will be copied
  Then I see counts: people, days, jobs, scheduled slots, backlog items

Scenario: jobs that will not repeat
  Given the plan holds an outside order, an exception child and a cancelled job
  Then each is listed as "will not repeat" with its reason, and cannot be ticked

Scenario: leave a job out
  When I untick a job
  Then the counts update and that job is not repeated

Scenario: a person who cannot come along
  Given a person on the plan is now inactive
  Then they are listed as "will be left off", with how many slots move to the backlog

Scenario: a map with no usable version
  Given a job's map is archived or has no published version
  Then the job is listed as "cannot repeat" with the reason

Scenario: a map that changed
  Given a job's map has a newer published version than the job used
  Then the job is listed as "will use the newer version"

Scenario: a start date that breaks the weekdays
  When I pick a start date that is not a whole number of weeks after the source start
  Then I am warned that weekdays will not line up, and I may continue

Scenario: a start date that overlaps
  When the new window would overlap the source plan's window
  Then it is refused with a message that says why

Scenario: the preview writes nothing
  Then no row is created or changed by opening or changing the preview

Scenario: another account
  Then it cannot preview my plan (not found)
```

- One read endpoint returns everything the screen shows. **The same function produces the preview
  and drives the real copy** (stories 02–04), so the preview cannot promise something the copy
  does not do.

## Counter-measures

| Risk | Prevention |
|---|---|
| The preview and the real copy disagree | One function builds the "repeat plan" (what, where, why not); the preview returns it, the copy executes it |
| The plan changes between preview and confirm | The copy rebuilds the list at confirm time and returns the **actual** result; the screen shows any difference from the preview |
| A long preview on a big plan | Counts by query (`return = {type: "count"}`), lists capped with "and N more" |
| The offered name is taken a moment later | The name is checked again at confirm; the unique index on (account, name) is the final guard |
| An archived plan is repeated | Allowed (an old plan is a good pattern), and said plainly in the preview |

## Governance

- **Errors (suggested):** `E-REPEAT-001` plan not found · `E-REPEAT-002` start date missing or not a date · `E-REPEAT-003` new window overlaps the source.
- **Events:** none for a read. A refused preview records `plan.repeat_preview` with outcome `rejected`.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-01-1 | Offered start date and name for a 7-day and a 14-day plan |
| T-REPEAT-01-2 | Counts match the plan |
| T-REPEAT-01-3 | Outside order, exception child, cancelled job listed and not tickable |
| T-REPEAT-01-4 | Inactive person and their slot count |
| T-REPEAT-01-5 | Archived map, no published version, newer version |
| T-REPEAT-01-6 | Weekday warning; overlap refusal |
| T-REPEAT-01-7 | Row counts on every plan table are the same before and after a preview |
| T-REPEAT-01-8 | Second account gets not-found |

## Keep a pulse on

- D-5 (which jobs repeat) is the builder's pick. If the founder wants outside orders to repeat, this story and story 03 change.
