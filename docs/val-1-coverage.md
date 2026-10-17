# VAL-1 coverage checklist (US-VAL-1-06)

One row per form/endpoint VAL-1 is meant to cover. Same sequencing
pattern as GOV-1's constraint matrix: most of these belong to epics
that **don't exist yet**, so they're listed here as a checklist to fill
in as each epic lands — not faked now.

**Status key:** ✅ covered · ⬜ not built yet.

| Form / endpoint | Fields | Rules in `fieldRules.json` | Owning epic | Status |
|---|---|---|---|---|
| `POST ops/event` | feature, step, outcome, severity, error_code, message, entity_type, entity_id, correlation_id, duration_ms | `ops_event.*` | OBS-1 | ✅ |
| `POST ops/feature_flag` | account_id, flag_key, note | `feature_flag.*` | GOV-1/VAL-1 | ✅ |
| Role form | name, type | — | ROLE-1 *(deferred)* | ⬜ |
| Stage contract | owner, exit_condition, completion_rule | — | STAGE-1 | ⬜ |
| Required-field authoring (task, duration, done-when) | — | — | AUTH-1 | ⬜ |
| Plan template | name, window_days, start_time | — | PLAN-1 | ⬜ |
| Plan instance | start date | — | PLAN-1 | ⬜ |
| Job + attributes | title, attributes | — | JOB-1 | ⬜ |
| Scheduling tweak | duration, reason | — | SCHED-1 | ⬜ |
| Publish to live | — | — | LIVE-1 | ⬜ |
| Performer actions | status, blocked reason | — | APP-1/LOG-1 | ⬜ |
| Variance filters | date range, stage, role | — | VAR-1 | ⬜ |

**Rule going forward (same as GOV-1):** the epic that builds a form adds
its own entries to `fieldRules.json` and ticks its row here. Don't
retrofit the whole list at the end.
