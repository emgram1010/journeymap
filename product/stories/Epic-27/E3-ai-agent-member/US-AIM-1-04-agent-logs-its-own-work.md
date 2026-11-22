# US-AIM-1-04 — The agent logs its own work

**Epic:** AIM-1 · **Size:** M · **Model:** **Opus 5.5**, then review (status engine) · **Status:** 📋 Not built
**Depends on:** US-AIM-1-03

## Description

There is no tool that records a step as started, done, blocked or skipped. So when an AI does
the work, the owner has to tick it off by hand, and plan vs actual says the owner did it. A
person already records a step through one endpoint (563), and one function (`log/next_status`)
decides which status changes are legal. The new tools must go through that same rule, or the
engine and the tools will one day disagree.

## User story

**As** the owner, **I want** the AI to mark its own steps started, done, blocked or skipped,
**so that** plan vs actual is true without me ticking for it.

## Acceptance criteria

```gherkin
Scenario: start and complete a step
  Given a live day assigned to the agent, with a step not started
  When the agent calls exec_start_step, and later exec_complete_step
  Then the step is in_progress, then done
  And actual minutes are the server's own time between the two events
  And the numbers appear under the agent in plan vs actual

Scenario: block or skip needs a reason
  When exec_block_step or exec_skip_step is called with no reason, or fewer than 5 characters
  Then it is refused and the message asks for a reason
  And with a reason, the reason is stored on the event

Scenario: someone else's day
  Given a live day assigned to another member
  When the agent calls any exec tool on a step of that day
  Then it is refused: "This step is on another member's day."

Scenario: a draft day
  Then it is refused: "This day is not live yet."

Scenario: a change the engine does not allow
  When the agent completes a step that was never started, or starts one that is done
  Then the engine's own refusal is returned, unchanged

Scenario: the same call twice
  When exec_start_step is called twice for the same step
  Then the second call changes nothing and says "already started"

Scenario: the agent cannot set the time
  Then the tools take no time input; the server stamps every event

Scenario: the log
  Then each action is in the activity log with the agent's name, the time and the item
  And the log can be filtered by member

Scenario: a step that needs approval
  Given a step whose action touches a customer, a booking or money
  Then the approval gate still applies before the action; marking the step done does not skip it
```

- Four tools: `exec_start_step`, `exec_complete_step`, `exec_block_step`, `exec_skip_step`.
  Each is a thin caller of the same function endpoint 563 uses.
- "Assigned to the calling agent" = the step's day belongs to a member whose `user_id` is the
  token's user. Resolved on the server from the token; the agent never passes its own member id.
- `performer_user_id` on the log row is the agent's user. The "0 for system or AI" note in the
  table description is updated once D-3 is confirmed.

## Counter-measures

| Risk | Prevention |
|---|---|
| The tools hold a second copy of the transition rule | They call `log/next_status` through the same function as endpoint 563; a test diffs all (status, event) pairs through both paths |
| An agent backdates work to look on time | No time inputs; server time only |
| A "done" 2 seconds after "start" makes the report look great | Record it honestly; VAR-1's outlier flag shows it. Do not hide or round it |
| An agent marks a person's step done | Ownership check is by the token's user against the day's member, on the server |
| The reason check passes an empty string because of loose null equality | Test `!= ""` and length explicitly; never `!= null` alone |
| A regression in people's recording | Record a person's plan-vs-actual for a fixed fixture before the change and compare after |
| Smoke tests use `0` as a timestamp and produce nonsense | Use a realistic epoch base plus minute offsets |
| A failed status write leaves the job's cached status wrong | The same sync the endpoint runs (`log/sync_job_status`) runs here; failure records a failure event |
| The log filter by member leaks other accounts | Filter inside the caller's account first, then by member |

## Governance

- **Errors (suggested):** `E-AIM-020` not your day · `E-AIM-021` day is not live ·
  `E-AIM-022` a reason is needed · engine codes from LOG-1 passed through unchanged.
- **Events:** the activity log row is the success record. Every refusal writes one event with
  the tool, the step and the reason code.
- **Delete behaviour:** none. The activity log is append-only.

## Tests (write first)

| ID | Test |
|---|---|
| T-AIM-04-1 | Eli starts and completes a step on its own live day; log names Eli |
| T-AIM-04-2 | Block and skip refuse a missing or too-short reason; accept and store a real one |
| T-AIM-04-3 | Another member's day refused; draft day refused |
| T-AIM-04-4 | Every (status, event) pair gives the same result through the tool and through endpoint 563 |
| T-AIM-04-5 | Duplicate call is a no-op |
| T-AIM-04-6 | Actual minutes equal the server time difference (realistic timestamps) |
| T-AIM-04-7 | A person's plan-vs-actual is identical before and after this story |
| T-AIM-04-8 | Activity log filter by member returns only that member, only this account |
| T-AIM-04-9 | An owner token calling an exec tool for the agent's step: decide and test (suggested: refused; the owner uses the screen) |
