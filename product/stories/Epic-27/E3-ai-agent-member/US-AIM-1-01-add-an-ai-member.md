# US-AIM-1-01 — Add an AI member in the app

**Epic:** AIM-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-AIM-1-00

## Description

The database already knows the difference between a person and an AI (`planner_agent.kind`),
but the add-member screen has no way to choose, so an AI agent is stored as a person. That
makes reports wrong (an AI's hours look like a person's) and lets USR-3's "a person must have
a login and a grant" rule fire on something that is not a person.

**Assumed:** the screen change. The frontend was not read. **Assumed:** the endpoint already
accepts `kind`; story 00 confirms.

## User story

**As** the owner, **I want** to choose Person or AI when I add a member, **so that** an AI
agent is stored as an AI and is never mistaken for a person.

## Acceptance criteria

```gherkin
Scenario: add a person (unchanged)
  When I add a member and do not touch the type
  Then the type is Person and everything works as today

Scenario: add an AI member
  When I choose AI, give a name and save
  Then the member is stored with kind "ai"
  And it shows an "AI" label wherever members are listed

Scenario: link an AI member to a login
  Given a login that is marked as an AI
  When I link it to the AI member
  Then the link is saved

Scenario: link an AI member to a person's login
  Given a login that belongs to a person
  When I try to link it to an AI member
  Then it is refused: "This login belongs to a person. An AI member needs its own AI login."

Scenario: link a person member to an AI login
  Then it is refused the same way, in the other direction

Scenario: a model on a person
  Then it is still refused, as PLN-5 does today

Scenario: change the type later
  Given a member with recorded work
  When I try to change Person to AI, or AI to Person
  Then it is refused: "This member has recorded work. Add a new member instead."

Scenario: existing members
  Then no existing member's type changes
```

- The plan tool `plan_add_person` gains an optional `kind` with the same rules, default `person`.
- The same login cannot be linked to two members of one plan (existing API check, kept).

## Counter-measures

| Risk | Prevention |
|---|---|
| A person's login labelled "AI" hides who really acted | The login's own kind must match the member's kind, checked on the server, not only in the screen |
| A unique index on `user_id` is added "to be safe" | Do not. Members with no login all hold 0. Keep the API check; add a test that proves it |
| An omitted `kind` cannot be told from an empty one | Treat `""` as "person" on create; on edit, read with the raw-input sentinel so "left out" means keep |
| Existing rows are rewritten | No backfill. The story changes only what a new save does |
| The screen allows it but the server does not, or the reverse | Server validates again; the form keeps what the owner typed when a save is refused |
| Changing kind rewrites history's meaning | Refused once any work is recorded (count query, like `assert_map_unused`) |

## Governance

- **Errors (suggested):** `E-AIM-001` login kind does not match member kind · `E-AIM-002` type
  cannot change after work is recorded · existing PLN-5 codes for name and model.
- **Events:** `planner_agent.created` / `.updated` with kind and whether a login is linked
  (no email). Failures record a failure event.
- **Delete behaviour:** unchanged. A member with recorded work is switched off, never deleted.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-01-1 | Default add stores `person`; existing flow unchanged |
| T-AIM-01-2 | AI add stores `ai` and shows the label (UI) |
| T-AIM-01-3 | Person login on an AI member refused; AI login on a person member refused |
| T-AIM-01-4 | Kind change refused after recorded work; allowed before |
| T-AIM-01-5 | Two members with no login in one plan still save (no unique index regression) |
| T-AIM-01-6 | `plan_add_person` with `kind: "ai"` behaves the same as the screen |
