# US-AIM-1-08 — It can never give itself more power

**Epic:** AIM-1 · **Size:** M · **Model:** **Opus 5.5**, then review · **Status:** 📋 Not built
**Depends on:** US-AIM-1-05 · **Threats:** T-2, T-3

## Description

The most dangerous thing an AI can do is not one bad action. It is quietly widening its own
access: issuing itself a new token, adding itself to another plan, raising its approval level,
creating a second AI, or approving its own waiting action. Any one of these turns every other
guardrail off. This story writes the AI **ceiling** down as one list the server enforces on
every call, and makes "no one approves their own work" a hard rule.

## User story

**As** an admin, **I want** an AI to be unable to widen its own access or approve anything,
**so that** every guardrail I set stays in place no matter what the AI is told or tries.

## Acceptance criteria

```gherkin
Scenario: the ceiling
  Then no AI login may ever, whatever its scope:
    | publish a map version or publish a plan to live |
    | delete, archive or restore anything             |
    | approve or reject any waiting action            |
    | create, edit or switch off a member or user     |
    | create, view or revoke a token                  |
    | change a password or start a reset              |
    | change roles, grants, approval levels or caps   |
    | change its own or another AI's scope or manager |
    | change account settings or feature flags        |
    | edit locked playbook entries (COP-11)           |
    | register or change a webhook or connection      |

Scenario: default deny
  Given a new tool is added with no declared action type
  Then an AI login is refused on it until someone adds it to the AI allow-list

Scenario: no self-approval, no AI approval
  Given an action is waiting for approval
  When any AI login tries to approve or reject it, its own or another AI's
  Then it is refused; only a person may decide

Scenario: separation of duties
  Given an AI drafted a change
  Then the person who approves it is shown that an AI drafted it

Scenario: scope is checked on the server
  When an AI calls a tool in its scope but on a plan outside its scope
  Then it is refused, even though the tool itself is allowed

Scenario: every refusal is logged
  Then the refusal names the AI, the tool, the target and the rule that refused it
  And counts toward the automatic pause (story 07)

Scenario: proof over the whole tool list
  Then an automated test calls every tool in the connector and the in-app copilot with an AI token
  And each one is either allowed by the list or refused, and the result matches the list exactly
```

- **One list, one place:** the AI allow-list and the ceiling live in one function the gate
  reads (`journey/tool_gate`). Story 05's scope picker shows only items under the ceiling.
- Changing the ceiling is a code change with an Opus review, never a setting.

## Counter-measures

| Risk | Prevention |
|---|---|
| A tool checks its own permission and forgets the AI case | No tool checks permissions itself; the gate does (COP-1's design) |
| An endpoint reachable outside the tool door lets an AI token in | AI tokens are accepted only at the tool door; every other endpoint refuses an AI-kind login. Tested on the full endpoint list |
| A new tool ships with no declared kind and is open by default | Default deny for AI logins; a test fails the build when a tool has no declared kind |
| An AI approves through a different path (screen endpoint, outside door) | The approve and reject endpoints refuse any AI-kind login, whichever door |
| Two AIs collude: one drafts, the other approves | No AI approves anything, so collusion has nothing to use |
| The ceiling drifts because it is copied into the UI | The UI reads the list from the server |
| Live and local gate differ | `getFunction` first; stop and ask if they differ |

## Governance

- **Errors (suggested):** `E-AIM-060` an AI can never do this · `E-AIM-061` outside this AI's
  scope · `E-AIM-062` only a person can approve.
- **Events:** `ai_member.refused` (rule, tool, target), `ai_member.suspicious_attempt` for ceiling hits.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-08-1 | Every ceiling action refused (table-driven over the list) |
| T-AIM-08-2 | Tool with no declared kind refused for an AI |
| T-AIM-08-3 | AI cannot approve its own or another AI's action, from any door |
| T-AIM-08-4 | Allowed tool on an out-of-scope plan refused |
| T-AIM-08-5 | Full tool list: allowed and refused exactly match the allow-list |
| T-AIM-08-6 | Every non-tool endpoint refuses an AI login |
| T-AIM-08-7 | Approver sees "drafted by AI" |
