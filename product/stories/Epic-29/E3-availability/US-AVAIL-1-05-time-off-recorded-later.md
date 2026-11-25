# US-AVAIL-1-05 — Time off recorded after work was assigned

**Epic:** AVAIL-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** stories 01–03; REPEAT-1 story 05 (the review mark)

## Description

Availability changes after a plan is made. Someone calls in sick on Sunday night; the plan for
Monday was finished on Friday. If the system only checks at the moment of assigning, that plan
is now wrong and nothing says so.

When time off or a working pattern is saved, this story finds the work it affects and marks it
"needs review" with the reason. It moves nothing by itself. A planner decides who takes the work.

A day that is already published to live is **never** changed. It is a promise already made to a
person; the planner is told, and republishes if the day has not been started.

## User story

**As** a planner, **I want** to be told when someone's time off lands on work I already gave
them, **so that** I can move it before the day arrives.

## Acceptance criteria

```gherkin
Scenario: time off over draft work
  Given Ana has 3 items on Tuesday, not published
  When an admin records Ana as away on Tuesday
  Then each of the 3 items is marked "needs review: Ana is away that day"
  And the admin is told "3 planned items are affected" before saving

Scenario: several plans
  Then affected work in every non-archived plan that covers those dates is marked

Scenario: a published day that has not been started
  Then nothing is changed
  And the planner sees "Ana is away on a day that is already live. Move the work and publish again."

Scenario: a published day that has been started
  Then nothing is changed, and the notice says the day is in progress

Scenario: a pattern change
  When Ana's pattern changes so she no longer works Fridays
  Then her future Friday work is marked; past days are left alone

Scenario: the time off is removed
  Then the marks this raised are cleared, and marks raised for other reasons stay

Scenario: the work is moved
  Then its mark is cleared

Scenario: the admin's count matches
  Then the number shown before saving equals the number of marks made

Scenario: Health page
  Then one line per person and plan shows work sitting on a day they are not available
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Marks are added to only the first matching item | Query the affected slots, loop by id, in the same transaction as the time off; the count is re-queried |
| The system quietly moves work | It never moves anything. It marks and tells |
| A published day is edited | The search skips published days and reports them separately; a test compares publication hashes before and after |
| Clearing on removal wipes marks raised by a repeat | Each mark stores what raised it; only marks raised by this time off are cleared |
| An item already marked gets a second mark | One mark per slot (unique); a second reason is added to the same mark |
| Past days get marked and clutter old plans | Only dates from today onward, by the plan's plain dates |
| The pre-save count and the result differ because the plan changed in between | The result is the truth; the screen shows the actual number after saving |
| A person with no profile link is missed | They have no time off to record; nothing to do |

## Governance

- **Errors:** none new.
- **Events:** `time_off.work_affected` (profile, dates, plans, count of items marked, count on published days), severity warn so it shows on the Health page.
- **Delete behaviour:** marks follow REPEAT-1 story 05.

## Tests (write first)

| ID | Test |
|---|---|
| T-AVAIL-05-1 | Draft work marked; count matches |
| T-AVAIL-05-2 | Two plans covering the dates both marked |
| T-AVAIL-05-3 | Published day untouched (hash equal); notice shown |
| T-AVAIL-05-4 | Pattern change marks future days only |
| T-AVAIL-05-5 | Removing time off clears only its own marks |
| T-AVAIL-05-6 | Already-marked item is not double-marked |
| T-AVAIL-05-7 | Health line appears and clears |

## Keep a pulse on

- "Suggest who could take this instead" is MATCH-1 story 02. Link the two screens once both exist.
