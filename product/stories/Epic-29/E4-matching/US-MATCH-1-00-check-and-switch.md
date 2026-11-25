# US-MATCH-1-00 — Find every path that assigns work, and build the switch

**Epic:** MATCH-1 · **Size:** M · **Model:** Opus 5.5 · **Status:** 📋 Not built
**Depends on:** REQ-1, AVAIL-1

## Description

Two things come before the rule itself.

**The list.** A refusal is only as good as its weakest door. README F-8 lists the paths found
on 2026-11-25 (live and repo matched), and names the one shared check most of them already call,
`planner_ops/assert_agent_assignable`. This story re-confirms that list at build time, proves or
clears the loop risk in F-17, and checks that every path reaches the shared check. A path that is
missed is a way around a hard need, and nobody would know until the wrong person turned up to do
the work.

**The switch.** Matching changes what planners are allowed to do. It must be possible to turn it
on per account, see what it would do before it does it, and turn it off in one step.

## User story

**As** the founder, **I want** matching to be off by default, with a dry run before it bites,
**so that** I can switch it on for one business without risk to the others.

## Acceptance criteria

```gherkin
Scenario: the list of paths
  When every live endpoint, function and AI tool is searched for writes that place work on a person or a day
  Then each one is listed with: what it writes, who calls it, and whether a person or an AI can reach it
  And the list is compared to README F-8 and any difference is reported

Scenario: off by default
  Given an account with no setting
  Then matching is off and nothing is checked

Scenario: show only
  When an admin sets "show only"
  Then suggestions and warnings appear and nothing is refused
  And each refusal that would have happened is counted for the Health page

Scenario: on
  When an admin sets "on"
  Then hard needs and availability are enforced

Scenario: switching on with a dry run first
  When an admin sets "on" without having used "show only"
  Then they are shown how many current assignments would be refused, and asked to confirm

Scenario: switching off
  Then enforcement stops at once; nothing already refused is changed; existing marks stay

Scenario: who may switch
  Then admins and the owner; an AI may not

Scenario: one read for everyone
  Then every check reads the setting through one function

Scenario: another account
  Then its setting is its own
```

## Counter-measures

| Risk | Prevention |
|---|---|
| A path is missed | The list is built by searching for the writes (`db.add`/`db.patch` on `planner_task`, `planner_task_work_task`, `planner_timeline`), not from memory. Story 03 adds a build guard that fails when a new file writes those tables without calling the rule |
| A missing settings row is read as "on" | No row = off. Read as `setting == "on"`, never with a null check (`"" == null` is true in this engine) |
| An untouched enum comes back as `""` and falls through a default | The read function maps anything that is not exactly `on` or `show_only` to off |
| The feature-flag table is changed to add a key | It is not touched; this is its own table |
| Switching on strands a plan mid-week | Switching on never changes existing assignments. It marks the ones that no longer fit for review (story 04) and says how many |
| An AI switches it off to get work done | Admin endpoint with `copilot/assert_person_only`; no tool |
| "Show only" counts are never looked at | They appear on the Health page and on the switch screen, beside the "on" button |

## Governance

- **Errors (suggested):** `E-MATCH-001` setting must be off, show only or on · `E-MATCH-002` a person must do this (AI refused).
- **Events:** `matching.setting_changed` (from, to, actor, the dry-run count shown). `matching.would_refuse` in show-only mode (path, reason), kept as counts.
- **Rollback:** set to off. No data is removed.

## Tests (write first)

| ID | Test |
|---|---|
| T-MATCH-00-1 | Path list recorded and compared to F-8 |
| T-MATCH-00-2 | No row = off; every F-8 endpoint unchanged (before/after) |
| T-MATCH-00-3 | Show only: nothing refused, counts recorded |
| T-MATCH-00-4 | On without a dry run asks to confirm with a count |
| T-MATCH-00-5 | Off again: enforcement stops, marks stay |
| T-MATCH-00-6 | AI caller refused; second account independent |
| T-MATCH-00-7 | Every F-8 path reaches `assert_agent_assignable` (or is listed as a day-only path) |
| T-MATCH-00-8 | F-17 loop risk: one live run per function with real estimate data; result recorded |

## Keep a pulse on

- How long accounts stay in "show only". If the would-refuse count stays high, the needs or the holdings are set up wrong, and "on" would hurt.
