# US-AIM-1-06 — Switch off, pause all AI, and offboard

**Epic:** AIM-1 · **Size:** M · **Model:** Opus 5.5 · **Status:** 📋 Not built
**Depends on:** US-AIM-1-03, US-AIM-1-05 · **Threats:** T-11, T-12

## Description

When an employee leaves, a careful business takes the keys back that day, hands their work to
someone else, and keeps their records. When something goes wrong, it can stop everyone at once.
COP-1 already gave the in-app copilot an off switch. This story extends it to every AI member,
adds one switch that stops **every** AI in the account, and defines what happens to the work an
AI leaves behind.

## User story

**As** an admin, **I want** to stop one AI, or every AI, in one press and have its work handed
back to a person, **so that** I am always in control and nothing is lost or left hanging.

## Acceptance criteria

```gherkin
Scenario: switch off one AI member
  When an admin switches off an AI member
  Then its next call is refused, whatever token or chat it comes from
  And every token it holds is revoked
  And its manager is notified

Scenario: its open work
  Given the AI had steps in progress and future steps on live days
  Then those steps are listed under "Work to reassign" for its manager and admins
  And nothing is reassigned automatically
  And steps in progress stay as they are until a person decides (finish, block or reassign)

Scenario: its history
  Then every job, step, log entry and approval the AI made is kept and still names it

Scenario: switch it back on
  When an admin switches it back on
  Then it can work again only after a new token is issued (old tokens stay revoked)

Scenario: pause all AI
  When an admin presses "Pause all AI" for the account
  Then every AI member's next call is refused with "AI is paused for this account."
  And scheduled AI runs and the order webhook's forwarding stop
  And incoming orders are queued, not lost
  And a banner shows on every page for admins until it is turned back on

Scenario: resume all AI
  When an admin turns it back on
  Then AI members work again with their existing tokens
  And queued orders are processed in order

Scenario: a non-admin
  Then they cannot switch off an AI or pause all AI

Scenario: an AI tries to switch anything off or on
  Then it is refused (story 08)
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A call already in flight finishes after the switch | Each write re-checks the switch inside the gate at the start; a call that started before is allowed to finish one write, never start another. Documented, not hidden |
| The switch is cached and keeps letting calls through | Read the switch on every call; no cache |
| Pause-all drops incoming orders | The webhook still receives and queues; only forwarding stops |
| Revoking tokens one by one half-applies | Query the agent's tokens, then revoke each by id inside one transaction; re-query to confirm none is live |
| Work is reassigned to someone without access | No automatic reassignment (USR-3's rule); a person reassigns through the normal screen, which checks access |
| Reactivation quietly restores old access | Old tokens stay revoked; a new token is required |
| Two switches disagree (COP-1's copilot switch and this one) | One switch, read by one function in the gate; COP-1's is extended, not duplicated |
| Pause-all is forgotten | A banner for admins and a Health warning after 24 hours paused |
| Admins cannot find it in an emergency | One button on the Team page and on the Health page |

## Governance

- **Errors (suggested):** `E-AIM-040` this AI member is switched off · `E-AIM-041` AI is paused for this account.
  COP-1's `E-COP-003` is reused if it already says the same thing.
- **Events:** `ai_member.switched_off`, `.switched_on`, `ai.paused_all`, `ai.resumed_all`
  (who, when, how many AI affected), `ai_member.tokens_revoked` (count).
- **Delete behaviour:** nothing is deleted. A switched-off AI member stays in history.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-06-1 | Switch off: next call refused from token and from chat |
| T-AIM-06-2 | All its tokens revoked (re-query) |
| T-AIM-06-3 | Open work listed, nothing reassigned automatically |
| T-AIM-06-4 | History unchanged (row counts before and after) |
| T-AIM-06-5 | Switch on needs a new token |
| T-AIM-06-6 | Pause all: every AI refused; webhook queues; banner shown |
| T-AIM-06-7 | Resume all: queued orders processed once, in order |
| T-AIM-06-8 | Non-admin and AI cannot use either switch |
