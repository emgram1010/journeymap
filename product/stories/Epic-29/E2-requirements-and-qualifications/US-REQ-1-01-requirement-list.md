# US-REQ-1-01 — One list of requirements per account

**Epic:** REQ-1 · **Size:** M · **Model:** Sonnet 5.5 · **Status:** ✅ Built (2026-11-26)
**Depends on:** story 00

## Description

A requirement is a name: something a person can hold and a step can need. For the two sides to
match, both must point at the **same** record. If the map designer types "Forklift" and the
admin types "fork lift licence", nothing ever matches and nobody is told why.

So requirements are picked from one list per account, never typed in place. The list has no
built-in types. A licence, a tool, a clearance and a language are all just entries.

## User story

**As** an owner or admin, **I want** one list of the things work can need and people can hold,
**so that** a need and a holding always mean the same thing.

## Acceptance criteria

```gherkin
Scenario: add a requirement
  When I add "Forklift" with a short description
  Then it is in my account's list

Scenario: same name, different case or spaces
  When I add "forklift" or " FORKLIFT "
  Then I am told it already exists, and the existing one is offered

Scenario: a bad name
  When the name is empty, longer than 60 characters, or contains HTML
  Then it is refused with a message that says why, and what I typed is kept

Scenario: rename
  When I rename "Forklift" to "Forklift licence"
  Then every step that needs it and every person who holds it shows the new name
  And published versions show the new name too, because they point at the record

Scenario: archive
  When I archive a requirement
  Then it can no longer be picked for a step or a person
  And it still shows wherever it is already used

Scenario: delete
  Given a requirement is used by a step, a person or a published version
  Then it cannot be deleted, and I am told how many places use it and offered archive
  Given it is used nowhere
  Then it can be deleted

Scenario: the limit
  When the account already has 200 requirements
  Then the next one is refused with the limit in the message

Scenario: who may edit
  Then admins and the owner may add, rename and archive; everyone in the account may read

Scenario: another account
  Then it cannot see, use or change my list
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Two requests add "forklift" at once | Unique index on (account, name key); the loser reads the winner's row |
| The lower-case key relies on a column filter a later schema change drops | The key is computed in one function and stored; no `filters=lower` |
| Near-duplicates ("Forklift", "Forklift licence", "FLT") | The add screen shows close matches before saving; an AI caller gets the matches and creates nothing unless it asks again (the TAG-1 pattern) |
| A rename changes the meaning under work already published | A rename is a label change only. Changing what a requirement **means** is a new requirement plus an archive; the rename screen says so |
| A delete orphans needs or holdings | Delete is refused while anything points at it; counts by query, not by loading rows |
| The list becomes an HTML injection point | VAL-1 field validation; shown escaped everywhere |
| An industry word is baked in | No type column, no seeded rows. The list starts empty |

## Governance

- **Errors (suggested):** `E-REQ-001` name empty or too long · `E-REQ-002` no HTML · `E-REQ-003` already exists · `E-REQ-004` in use, cannot delete · `E-REQ-005` account has 200 · `E-REQ-006` not found.
- **Events:** `requirement.created`, `.renamed`, `.archived`, `.restored`, `.deleted`. Failures record a failure event.
- **Delete behaviour:** blocked while used anywhere; archive instead.

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-01-1 | Add, list, rename, archive, restore |
| T-REQ-01-2 | Case and spaces make one requirement |
| T-REQ-01-3 | Name rules and the limit |
| T-REQ-01-4 | Delete refused when used by a step, a person, a version; allowed when unused |
| T-REQ-01-5 | Two parallel adds leave one |
| T-REQ-01-6 | Archived not offered in pickers, still shown where used |
| T-REQ-01-7 | Non-admin cannot write; second account sees nothing |
| T-REQ-01-8 | AI near-match creates nothing |

## Keep a pulse on

- If owners ask to group requirements, reuse the tag pattern (TAG-1). Do not add a type column.
