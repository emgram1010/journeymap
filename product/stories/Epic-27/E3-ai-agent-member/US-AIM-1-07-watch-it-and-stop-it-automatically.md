# US-AIM-1-07 — Watch it, and stop it automatically

**Epic:** AIM-1 · **Size:** M · **Model:** Sonnet 5.5, Opus review · **Status:** 📋 Not built
**Depends on:** US-AIM-1-05, US-AIM-1-06 · **Threats:** T-5, T-8

## Description

An AI works faster than any person and does not get tired, so when it goes wrong it goes wrong
at scale: a loop that adds the same job 300 times, or keeps hammering a tool it is not allowed
to use. A manager cannot watch every call. This story gives the manager a clear picture of what
each AI did, and makes the system pause an AI by itself when its behaviour looks wrong.

COP-1 already has a daily cap and a log for the copilot. This story extends both to every AI
member and adds the automatic pause.

## User story

**As** an AI member's manager, **I want** to see what it did and have it paused automatically
when it misbehaves, **so that** a mistake is caught in minutes, not discovered next week.

## Acceptance criteria

```gherkin
Scenario: caps
  Given each AI member has a cap on writes per hour and per day (suggested 60 and 400)
  When it reaches a cap
  Then further writes are refused until the window resets
  And reads still work
  And its manager is notified once, not once per refused call

Scenario: automatic pause on repeated refusals
  Given an AI is refused 10 times in 10 minutes for scope or permission reasons
  Then it is paused automatically
  And its manager and admins are notified with the last refusals
  And it stays paused until a person resumes it

Scenario: automatic pause on a suspicious attempt
  Given an AI tries a ceiling action (publish, delete, approve, permissions, tokens, passwords, settings)
  Then it is refused and logged as suspicious
  And after 3 suspicious attempts in a day it is paused automatically

Scenario: the activity panel
  When a manager or admin opens an AI member
  Then they see today and the last 7 days: calls, writes, refusals, approvals waiting, steps done
  And the last 50 actions, each with time, tool, target and outcome

Scenario: the weekly digest
  Then every Monday the manager gets a short summary per AI: what it did, what was refused, anything paused

Scenario: the Health page
  Then admins see every AI member that is paused, capped, near its cap, or has suspicious attempts

Scenario: caps can be changed
  When an admin changes an AI's caps
  Then the change is logged with before and after, and can never exceed the account maximum (suggested 200 per hour)
```

## Counter-measures

| Risk | Prevention |
|---|---|
| Counting needs redis (not available) | Count rows in the tool log since a cutoff held in a `var`; `return = {type: "count"}` |
| A filter call inside a `where` clause fails silently | Compute the cutoff into a `var` first |
| The automatic pause itself fails silently | Writing the pause is a checked step that records success or failure; a failure raises a Health warning |
| Notifications spam the manager | One notification per kind per AI per hour |
| The digest task fails silently | It writes a heartbeat every run; Health warns if a Monday run is missing |
| A person's work is slowed by the counting | Counts are per AI login only; people's calls skip it |
| Caps are set so high they mean nothing | An account maximum the server enforces |
| The panel shows other accounts' AI | Scoped to the caller's account |
| The refusal counter counts honest mistakes (a bad date) as misbehaviour | Only scope, permission and ceiling refusals count toward the pause, not input errors |

## Governance

- **Errors (suggested):** `E-AIM-050` hourly cap reached · `E-AIM-051` daily cap reached ·
  `E-AIM-052` paused automatically after repeated refusals. COP-1's `E-COP-004` reused where it fits.
- **Events:** `ai_member.capped`, `.auto_paused` (reason, last refusals), `.suspicious_attempt`
  (tool, target), `.resumed` (by whom), `ai.digest_sent`.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-07-1 | Hourly and daily caps refuse writes, allow reads, notify once |
| T-AIM-07-2 | 10 scope refusals in 10 minutes pause the AI |
| T-AIM-07-3 | 3 ceiling attempts in a day pause the AI |
| T-AIM-07-4 | Input errors do not count toward the pause |
| T-AIM-07-5 | Activity panel numbers match the log |
| T-AIM-07-6 | Digest sent once per Monday, with a heartbeat |
| T-AIM-07-7 | Cap change logged; above account maximum refused |
| T-AIM-07-8 | People's calls are not counted or slowed |
