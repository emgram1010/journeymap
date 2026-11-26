# US-REPEAT-1-07 — An AI can draft a repeat

**Epic:** REPEAT-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** ✅ Built (2026-11-26)
**Depends on:** stories 01–04

## Description

The connector and the copilot can already list plans, read one, add jobs and schedule steps.
"Set up next week like this week" is exactly the kind of request a person will type. Without a
tool, the AI rebuilds the week one call at a time, slowly and with mistakes.

The tool does what the screen does and nothing more: it previews, and it drafts. It does not
publish, and it does not clear review marks.

## User story

**As** an owner, **I want** to ask the AI to set up the next period from the last one,
**so that** I get a draft to review without clicking through the planner.

## Acceptance criteria

```gherkin
Scenario: preview
  When the AI calls plan_repeat with preview only
  Then it gets the same counts and "will not repeat" list the screen shows, and nothing is written

Scenario: draft
  When the AI calls plan_repeat to create
  Then the new plan exists as drafts, every copied slot marked needs review
  And the answer says what was left out and why, in plain words

Scenario: it is told what it may not do
  Then the answer says the plan is a draft and a person must review and Publish to live

Scenario: an AI member limited to some plans
  Given the AI may only work in plans 146 and 147
  When it tries to repeat another plan
  Then it is refused

Scenario: the new plan and the AI's plan list
  Given an AI member limited to listed plans
  Then the new plan is NOT added to its list by the repeat

Scenario: approval level
  Then the tool runs at the level the account set for "create a plan"

Scenario: caps
  Then a repeat counts against the AI's hourly and daily write caps as one write per plan made
```

- Goes through `journey/tool_gate` as a write, with a declared action type. Added to the connector and both copilots.

## Counter-measures

| Risk | Prevention |
|---|---|
| The tool has its own copy of the repeat logic | It calls the same function the endpoint calls |
| An AI gives itself access to the new plan | The repeat never edits `ai_member_profile.plan_ids`; only an admin does (AIM-1 story 08) |
| An AI repeats eight periods in a loop | Periods are capped at 8 per call, and each plan counts against the caps |
| An omitted optional input is read as empty and changes the request | Read optional inputs from the raw input with a sentinel, never `$input.x != null` |
| The AI reports success when half was left out | The answer leads with the left-out list when it is not empty |

## Governance

- **Errors:** the same codes as the screen.
- **Events:** the same `plan.repeated`, with the AI as the actor and its manager recorded.

## Tests (write first)

| ID | Test |
|---|---|
| T-REPEAT-07-1 | Preview writes nothing |
| T-REPEAT-07-2 | Draft matches a repeat made from the screen |
| T-REPEAT-07-3 | AI limited to plans is refused outside them |
| T-REPEAT-07-4 | `plan_ids` unchanged after a repeat |
| T-REPEAT-07-5 | Caps counted |
| T-REPEAT-07-6 | Tool present in the connector and both copilots |

## Keep a pulse on

- Whether an AI that drafted next period should be allowed to work in it is the manager's call, made on the AI member's own settings.
