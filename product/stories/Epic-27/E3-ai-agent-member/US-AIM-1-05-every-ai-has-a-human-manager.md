# US-AIM-1-05 — Every AI member has a human manager and a job description

**Epic:** AIM-1 · **Size:** S · **Model:** Opus 5.5 · **Status:** 📋 Not built
**Depends on:** US-AIM-1-00 · **Answers:** USR-3's open question "Does an AI agent need an owning user?"
**Threats:** T-9 (unsupervised AI), and the accountability behind T-2, T-5 and T-8.

## Description

A new employee has a manager who is answerable for their work and a job description that says
what they are there to do. Today nothing records who is responsible for an AI agent, so when it
does something wrong there is nobody to tell and nothing to check against.

This story makes both required. The manager is a real, active person in the account. The job
description is the AI's **scope**: which plans it may work in and which kinds of action it may
take, chosen from a fixed list, never more than the AI ceiling in story 08.

## User story

**As** an admin, **I want** every AI member to have a named human manager and a written scope,
**so that** someone is always answerable for what it does and it can never drift beyond the job
it was given.

## Acceptance criteria

```gherkin
Scenario: create an AI member
  When an admin creates an AI member
  Then a manager is required: an active person in this account
  And a scope is required: one or more plans, and a set of allowed actions chosen from a fixed list
  And a short purpose is required ("Prepares orders for Blooming", up to 200 characters)
  And the AI member cannot be saved without all three

Scenario: the scope can never exceed the AI ceiling
  When an admin ticks an action that no AI may ever take (publish, delete, approve, permissions, tokens, passwords, settings)
  Then it is not offered, and the server refuses it if sent

Scenario: the manager is told
  When an AI member is created, or its scope or manager changes
  Then the manager is notified, and the change is logged with before and after

Scenario: the manager is switched off or leaves
  Given the manager is switched off, deleted or loses their access
  Then every AI member they manage is paused on its next call
  And admins see "Needs a new manager" on the Health page
  And the AI resumes only when an admin names a new active manager

Scenario: the AI cannot change its own job
  When an AI login tries to change its own manager, purpose or scope
  Then it is refused (story 08) and logged

Scenario: a new AI starts cautious (⏸ ON HOLD, founder 2026-11-21: kept here, do not build until confirmed)
  Given an AI member created in the last 14 days
  Then every write it makes waits for its manager's approval, whatever the account's usual level
  And after 14 days the account's usual approval levels apply

Scenario: existing AI members
  Given AI members that existed before this story
  Then they are listed on the Health page as "Needs a manager" and paused until one is named
  And the founder is told before this is switched on, with the list
```

- Manager and scope live on a new 1:1 side table (suggested `ai_member_profile`: member,
  manager user, purpose, allowed actions, allowed plan ids, created by, probation ends at).
  No column on `planner_agent` or `user`.
- The allowed-action list is the same list the gate reads (story 08). One list, one place.

## Counter-measures

| Risk | Prevention |
|---|---|
| Existing AI work stops without warning | Pausing existing AI members is behind a flag; the founder sees the list first and turns it on |
| The manager is an AI | Server check: the manager's login kind must be person |
| The manager is in another account | Server check: same account |
| Scope stored as free text that nobody enforces | Scope is a fixed list of action types and a list of plan ids; the gate enforces it on every call |
| A new column on `user` drops its validators | Side table only |
| A paused AI keeps scheduled runs going | The pause is checked in the one gate every call passes, including scheduled runs (COP-5) |
| Probation is skipped by deleting and re-creating the AI | Probation follows the login, not the member row |
| An omitted list input cannot be told from an empty one | Lists are required inputs; an empty list is refused with a friendly message |

## Governance

- **Errors (suggested):** `E-AIM-030` manager required · `E-AIM-031` manager must be an active
  person in this account · `E-AIM-032` scope required · `E-AIM-033` that action is never allowed for an AI ·
  `E-AIM-034` paused: needs a new manager.
- **Events:** `ai_member.created`, `.scope_changed` (before/after), `.manager_changed`,
  `.paused_no_manager`, `.probation_ended`.
- **Delete behaviour:** the profile row stays while the member exists; it is never deleted while history exists.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-05-1 | AI member cannot be saved without manager, scope and purpose |
| T-AIM-05-2 | Manager who is an AI, or in another account, is refused |
| T-AIM-05-3 | Ceiling actions are refused even if sent |
| T-AIM-05-4 | Manager switched off → AI paused on next call; new manager → resumes |
| T-AIM-05-5 | AI changing its own scope is refused |
| T-AIM-05-6 | Probation: writes wait for approval for 14 days, then normal |
| T-AIM-05-7 | Existing AI members listed and paused only after the flag is on |
| T-AIM-05-8 | Scope and manager changes are logged with before and after |
