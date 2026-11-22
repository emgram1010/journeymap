# US-AIM-1-03 — The connector acts as the agent

**Epic:** AIM-1 · **Size:** M · **Model:** **Opus 5.5**, then review · **Status:** 📋 Not built
**Depends on:** US-AIM-1-00, US-AIM-1-01 · **Decision D-4 (do tokens expire): ⏸ on hold.**
Ask the founder before building; the suggestion is 90 days with a warning 7 days before. The
expiry scenario below is written for that suggestion and changes if the answer does.

## Description

An outside AI connects with the owner's credential, so every record it creates says the owner
did it. The owner cannot tell their own work from the AI's, and cannot switch the AI off
without switching themselves off. COP-1 already checks a token at the outside door
(`usr/mcp_caller`) and already has a gate every tool passes. What is missing is a credential
that belongs to **one AI member**, can do **less** than the owner, and can be taken away.

**Who manages tokens (founder, 2026-11-21):** any team admin, matching D-2. The AI itself never can (story 08).

## User story

**As** an admin, **I want** the AI to use its own credential, **so that** its actions are
logged under its name, not mine, and I can cut it off without touching my own access.

## Acceptance criteria

```gherkin
Scenario: issue a token
  Given an AI member with an AI login, a manager and a scope (story 05)
  When an admin chooses "Create access token" for it
  Then the token is shown once, with a copy button
  And only a hash of it is stored
  And the AI's manager is notified that a token was created, by whom

Scenario: a narrower token
  When an admin creates a token
  Then they may narrow it further than the AI's scope (for example "only add on-demand jobs to plan 146")
  And the token can never be wider than the AI's scope

Scenario: limited number of tokens
  Then an AI member may hold at most 2 live tokens; a third is refused until one is revoked

Scenario: last used
  Then each token shows when it was created, by whom, and when it was last used

Scenario: the agent acts
  When the connector calls a tool with the agent's token
  Then the gate identifies the agent's user, not the owner
  And records the agent creates or changes store the agent's user as creator
  And the tool log names the agent

Scenario: what the token may do
  Then it may read maps and plans in its account
  And write drafts (cells on a draft map, jobs and steps on a draft day)
  And record its own execution (story 04)

Scenario: what the token may not do
  When the agent calls publish (map or plan), delete, archive, restore, a permission change,
       an approval decision, a token or password action, or a member change
  Then the call is refused with a friendly message and a logged event

Scenario: the agent cannot approve itself
  Given an action of the agent is waiting for approval
  When the agent tries to approve it
  Then it is refused; only a person can approve

Scenario: revoke
  When an admin revokes the token
  Then the very next call with it is refused
  And every record and log entry the agent made is still there

Scenario: the member is switched off
  Then its token stops working until the member is switched back on

Scenario: expiry (D-4, suggested 90 days)
  Then an expired token is refused with "This access token has expired. Ask the owner for a new one."
  And the manager and admins are warned 7 days before

Scenario: a person's login
  When someone asks for an access token for a person
  Then it is refused; these tokens are for AI logins only
```

- Scope is checked in **one place**, the gate, from each tool's declared `kind` and `act_type`. No tool does its own scope check.
- A new tool with no declared kind is refused for an agent token by default.
- The owner's approval levels (COP-2) still apply on top of the scope.

## Counter-measures

| Risk | Prevention |
|---|---|
| A second identity system grows next to COP-1's | Extend `usr/mcp_caller` and `journey/tool_gate`; add no parallel gate |
| The token leaks through a URL (the door also accepts `?token=`) | Agent tokens are accepted in the `Authorization` header only; refuse them in the address |
| The token is stored readable | Store a hash; compare hashes; show the token once |
| The token appears in a log | Never written to `event_log`, tool logs, approval payloads or error text; a test searches for it |
| A token minted the wrong way is rejected live ("Invalid token.") | Prove the whole path over real HTTP before trusting it (CLAUDE.md, token note) |
| The agent reaches another account | The token resolves to one user in one account; tenancy checks are unchanged and tested with two accounts |
| The agent gives itself more power | No token, password, role, grant or approval tool is in scope, and the gate's default is refuse |
| A model is tricked by text in a cell into a forbidden call | The server refuses by scope; the refusal is logged with the tool name |
| A runaway agent floods the plan | COP-1's daily cap and off switch apply to this login too |
| Two requests overlap on revoke | Revocation is a single row state read on every call; no cache |
| The agent's login is used to sign in to the web app | **Decision inside D-3:** suggested no; an AI login has no password sign-in, only tokens and the owner's one-time reset link |

## Governance

- **Errors (suggested):** `E-AIM-010` not in this token's scope · `E-AIM-011` token revoked ·
  `E-AIM-012` token expired · `E-AIM-013` tokens are for AI logins only · `E-AIM-014` member is switched off.
- **Events:** `agent_token.created`, `.revoked`, `.expired`, `.refused` (with tool name and reason).
  Each names the owner who acted and the agent. No token value.
- **Table (new, additive):** `agent_access_token` with user id, account id, hash, created by,
  created at, expires at, revoked at, last used at, and an optional narrower scope (action types, plan ids). Unique index on the hash. Delete behaviour:
  rows are kept when revoked (history); removed only with the user.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-03-1 | Token call is attributed to user 34, not user 2 (real HTTP) |
| T-AIM-03-2 | A record created by the agent has the agent as creator |
| T-AIM-03-3 | Every out-of-scope tool is refused (a table-driven test over the full tool list) |
| T-AIM-03-4 | A tool with no declared kind is refused for an agent token |
| T-AIM-03-5 | The agent cannot approve its own waiting action |
| T-AIM-03-6 | Revoke: next call refused; history intact (row counts before and after) |
| T-AIM-03-7 | Token in the URL is refused; token in the header works |
| T-AIM-03-8 | Second account: the agent sees and changes nothing there |
| T-AIM-03-9 | No stored row or log contains the raw token |
| T-AIM-03-10 | The owner's own calls behave exactly as before |
| T-AIM-03-11 | A narrowed token is refused outside its narrower scope; a token wider than the AI's scope cannot be created |
| T-AIM-03-12 | Third live token refused |
| T-AIM-03-13 | Manager notified on token creation; last-used time updates |
| T-AIM-03-14 | A non-admin cannot create or revoke tokens |
