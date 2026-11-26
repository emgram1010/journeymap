# US-REQ-1-03 — A person on a plan knows their lasting profile

**Epic:** REQ-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** ✅ Built (2026-11-26)
**Depends on:** story 00 (its counts)

## Description

Holdings and working days sit on the lasting profile. Work is given to a **person on a plan**,
which is a fresh row in every plan. Today nothing ties the two together: when a plan is made from
a template, the profile's name, colour and hours are copied and the profile's id is thrown away
(confirmed live 2026-11-25: endpoint 551 has the id in hand at `551.xs:455-466` and does not keep
it; it does not copy `model_id` either). So the template path is the easiest link to add.

A person with a login can be found again through that login. An AI profile with no login cannot,
and neither can someone typed straight into a plan. Without a link, those people hold nothing as
far as the system can tell.

This story adds the link as a small side table and fills it in three ways: at the moment a person
joins a plan (from now on), by login (for existing plans, safe), and by an admin's hand (for the
rest).

## User story

**As** an admin, **I want** every person on a plan tied to their profile,
**so that** what they hold and when they work follows them into every plan.

## Acceptance criteria

```gherkin
Scenario: a plan made from a template
  Then every person copied from the roster is linked to the profile they came from

Scenario: a person added to a plan by picking a profile
  Then they are linked

Scenario: a repeated plan
  Then each person carries the link their source row had

Scenario: existing plans, people with a login
  When the one-time fill runs
  Then each person whose login has exactly one profile is linked to it

Scenario: existing plans, people with no login
  Then they are listed for an admin as "not linked", with profiles of the same name offered
  And nothing is linked by name unless the admin confirms each one

Scenario: a login with two profiles
  Then nothing is linked and it is listed for an admin

Scenario: link by hand, and unlink
  Then an admin can set or clear a link, and it is recorded

Scenario: a profile from another account
  Then it cannot be linked

Scenario: someone with no link
  Then they hold nothing and have no working pattern of their own
  And the plan's people list shows "no profile" beside them

Scenario: the fill is run twice
  Then the second run changes nothing

Scenario: a person on a plan is deleted
  Then their link goes with them
```

- The fill is tried first on a **clone** of real data, and reports counts before it writes.

## Counter-measures

| Risk | Prevention |
|---|---|
| Name matching ties two different people | Never automatic. Names are only offered; a person confirms each link |
| The fill links across accounts | Every link checks the profile's account against the plan's account |
| The fill half-runs | It is safe to re-run (unique index on the person on a plan; existing links are skipped); it reports linked, skipped and left for a person |
| A branch in the fill loop reads a variable updated earlier in the same pass and silently links nothing | Two passes, branching on the loop item's own field |
| The plan's people list does not read the side table, so "no profile" never shows | The people endpoint (534) returns the link; a dedicated read is wired to the screen (AUTH-1 lesson) |
| The template endpoint (551) is changed and breaks plan creation | One added write inside its existing transaction; its existing tests run before and after |
| A profile is deleted and leaves links pointing at nothing | Profile delete removes its links (query, loop by id) in the same transaction |
| An unlinked person silently cannot be given hard-need work once matching is on | MATCH-1's reason reads "no profile, so nothing is recorded as held", with a link to fix it |

## Governance

- **Errors (suggested):** `E-REQ-020` profile not found · `E-REQ-021` profile belongs to another account.
- **Events:** `plan_person.linked`, `.unlinked` (with who and how: template, picked, repeat, fill, by hand). The fill writes one summary event with its counts.
- **Rollback:** the side table can be emptied with no effect on any existing screen.

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-03-1 | Template instance links every copied person |
| T-REQ-03-2 | Add by profile links; add by hand does not |
| T-REQ-03-3 | Fill: one login one profile linked; no login listed; two profiles listed |
| T-REQ-03-4 | Fill twice changes nothing |
| T-REQ-03-5 | Cross-account link refused |
| T-REQ-03-6 | People list returns the link and "no profile" |
| T-REQ-03-7 | Deleting a person or a profile removes the link |
| T-REQ-03-8 | Existing template tests still pass |

## Keep a pulse on

- This link is also what AVAIL-1 needs. If REQ-1 is delayed, build this story first anyway.
