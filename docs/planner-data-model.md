# Planner data model (PLN-1, amended by P3A-1)

The six tables the planner is built on, what each column means, what the
database enforces, and — just as important — **what it cannot enforce and
who does instead**.

Built 2026-10-14. Every rule below was verified against the live workspace,
not just written down.

## Table ids

| Table | Live id |
|---|---|
| `planner_settings` | 113 |
| `planner_model` | 114 |
| `planner_workspace` | 115 |
| `planner_agent` | 116 |
| `planner_timeline` | 117 |
| `planner_task` | 118 |

`EPIC-PLN-1` reserved 74–79. Those ids were already taken by an unrelated
live initiative, and **Xano assigns table ids itself and ignores whatever a
plan asks for** — exactly as PUB-1 asked for 82 and got 112. The ids above
are the real ones; the reserved numbers were never more than a wish. See
`product/learning-fixes.md`.

## Shape

```
account ──┬── planner_settings      (1:1, unique account_id)
          ├── planner_model         (1:N, unique account_id + model_key)
          └── planner_workspace     (1:N, unique account_id + name)
                   │
                   ├── planner_agent     (1:N, unique workspace_id + name)
                   │        │
                   │        └── planner_timeline  (1:N, unique agent_id + planned_date)
                   │                   │
                   └───────────────────┴── planner_task  (timeline_id 0 = backlog)
```

## What the database enforces

| Rule | How | Verified |
|---|---|---|
| One settings row per account | unique `(account_id)` | FT-PLN-1-01 — second insert rejected |
| Model keys unique per account, reusable across accounts | unique `(account_id, model_key)` | FT-PLN-1-02 — rejected in one account, accepted in another |
| Plan names unique per account | unique `(account_id, name)` | FT-PLN-1-03 — rejected |
| Agent names unique per plan | unique `(workspace_id, name)` | FT-PLN-1-04 — rejected |
| One timeline per agent per day | unique `(agent_id, planned_date)` | FT-PLN-1-05 — second rejected |
| Every foreign key is indexed | GOV-1 standard S3 | schema audit, green |

## What it cannot enforce, and who does

| Rule | Owner |
|---|---|
| `planning_window_end >= planning_window_start` | PLN-3 |
| Workspace `name` required and non-blank | PLN-3 |
| `model_id` only on `kind = "ai"` agents | PLN-5 |
| One login (`user_id`) per agent per plan | PLN-5 / APP-1 — see "nullable FKs" below |
| Rates and `human_hourly_rate` non-negative | PLN-4 |
| `duration_minutes > 0` | PLN-7 |
| `start_time` is a valid `HH:MM` | PLN-6 |
| `seq` dense and unique within a timeline | PLN-7's resequence function |
| `title` required when a task is not linked to a job | PLN-7 / JOB-1 |
| Delete becomes archive once history exists | P3A-1 (US-P3A-1-02/03/04) |

## Two things that bite, written down once

**There are no real nullable foreign keys.** An `int` column in this Xano
workspace cannot hold a true `null` — it defaults to `0`. So every
"nullable FK" in the epics is really "`0` means not set":

- `planner_task.timeline_id = 0` → the task is in the backlog
- `planner_task.assignee_agent_id = 0` → inherit the timeline's agent
- `planner_agent.model_id = 0` → no model
- `planner_agent.user_id = 0` → no login yet
- `planner_workspace.plan_template_id = 0` → not created from a template

This is why `planner_agent` has **no** unique index on
`(workspace_id, user_id)`, even though US-P3A-1-01 asked for one: with
`0` standing in for null, the second agent in a plan that has no login
would collide with the first. Confirmed live — two agents with no login
insert fine under the current index set, and would not have under the
specified one. The "one login per agent" rule is enforced in the API.

**`planner_workspace.plan_template_id` is deliberately not a declared
reference.** `plan_template` is PLAN-1's table and does not exist yet.
Declaring the reference later would mean `updateTableSchema`, which
silently drops this table's `trim` validators (CLAUDE.md). PLAN-1's
endpoints enforce the relationship instead.

## Deviations from EPIC-PLN-1 as written

| Change | Why |
|---|---|
| `planner_model` gained `updated_at` | Rates are editable (PLN-4), so the table is not append-only and GOV-1 standard S2 requires it |
| No unique `(workspace_id, user_id)` on `planner_agent` | Would reject every second login-less agent — see above |
| `planner_timeline.status` and `planner_task.status` have **no** schema default | Both were specified as `draft` / `planned`. Adding a default now needs `updateTableSchema` (drops validators) or a table recreate. PLN-6 and PLN-7 write the value explicitly on every create. **Open:** worth a dashboard edit to add the defaults properly |
| Table ids 113–118, not 74–79 | Xano assigns ids |

## Seeding

Nothing is seeded at migration time (US-PLN-1-07). The first
`GET planner/settings` (PLN-4) lazily creates the settings row and the four
default models. The planner frontend's `INITIAL_*` demo data stays
frontend-only, for PLN-9's one-time import preview.

## Test fixture left in place

Account 3 ("PUB-1 QA Test Account") holds a small planner fixture created
while verifying this epic: one settings row, one model, workspace 1
("Q1 Delivery Plan"), two agents ("Rochelle" person, "Quote Bot" ai),
one timeline on 2026-10-20, and one backlog task. Kept deliberately — it
is useful for PLN-3 onward. It is test data, not customer data.
