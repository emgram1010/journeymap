# Emgram — Instructions for AI sessions

## Start here
1. Read `product/emgramprd.md` §0 (orientation), §10 (settled decisions) and §13 (next steps).
2. For build work, read `product/stories/phase-4/README.md`, then the epic file you are working on.
3. Do not ask the founder to re-explain the vision. If something is unclear, check the PRD first, then ask **one** short question.

## About the founder
- Product manager, **not an engineer**, and the only support person. ADHD/INTP-leaning.
- Keep answers **short and scannable**: lead with the decision, use tables, ask **one clear question at a time**.
- Explain in plain language. No jargon, no walls of text.
- **Explain before writing.** If asked to explain or review, answer in chat; do not create or edit files until asked.
- Treat their statements as direction, not gospel: validate, refine, point out gaps, then ask.
- Their examples are **illustrations**. Design the generic pattern; never build for a literal example (no industry assumptions).

## Build protocol (one epic at a time)
1. Work in the **MVP build order** in `product/stories/phase-4/README.md`. Do not start an epic whose dependencies are not done. Build only the stories marked in the epic's **MVP scope**; deferred stories wait.
2. **Write the epic's tests first** (unit, functional, UI as listed), then the code.
3. Every epic includes its **Governance section**: table constraints and delete behaviour, validation with friendly messages, error codes in the catalog, and success/failure events. Do not skip it.
4. Run the new tests **and** the existing suites (`npm test` in `webapp/protype-2`, `workflow_tests/1–12`, existing Playwright specs). All must be green before moving on.
5. Record results in the epic's **Test Results** section.
6. When an epic's completion gate passes, say so and wait for the founder before starting the next.

## Safety rules
- **Ask before**: any Xano schema push, any change to an existing table, any delete, any outward-facing action.
- Changes to existing tables are **additive only**, behind a flag where specified, with a rollback.
- Test migrations and backfills on a **clone** of map 178 (`leads-to-sales-baseline`), never the original.
- **Never overwrite or edit** files in `product/validation-publish-execution/` without asking. It overlaps this work; the overlap decisions are in PRD §8.6 (D-39).
- Do not edit documents that were not part of the request. If you find a mistake in an earlier document, say so and ask before fixing.
- Verify what already exists (tables, fields, logging) **before** adding anything. Reuse and extend; do not duplicate (example: extend `event_log`, do not create a second log).
- Never fail silently. Every important step records a success or a failure event (OBS-1).

## XanoScript constraints — verified live, workspace 1 (2026-10-13, during OBS-1)

These were learned the hard way by pushing OBS-1 and hitting real runtime errors. Follow them; don't re-discover them.

- **An omitted optional input is `""` / `0`, never `null`.** `$input.x ?? fallback` will NOT trigger for an omitted optional `text`/`int` field — it already holds `""`/`0` by the time the stack runs. Always check `$input.x != null && $input.x != ""` (text) or `!= 0` (int) explicitly; never rely on `??` for "was this provided".
- **`db.query`'s `return: {type: "list", paging: {...}}` does NOT produce a plain array.** `foreach` and `[index]` access on it both fail with `"Please use a numerically indexed array."`. Use `return: {type: "list"}` with **no `paging`** — confirmed working. If you need "just the latest row" or a capped count, loop with `foreach`/`each` and a found-flag or counter instead of paging + indexing.
- **`[index]` indexing into any script-built array (e.g. one built with `array.push`) is unreliable** — failed with the same `"numerically indexed array"` error even on a plain `var $arr { value = [] }` built via `array.push` in a loop. Don't index by position at all; track "the first/last value seen" with a `var`/`var.update` inside the same loop instead.
- **`array.map` + `array.group_by` + `object.entries` chained together, with nested `$this[1][0].field` indexing, broke live** (`"Missing var entry: this"` / `"Unable to locate var: $this.created_at"`) as soon as real (non-empty) data flowed through — passed with an empty array, failed with one row. Don't trust these docs-only examples without a live, non-empty-data test. The safe, confirmed alternative for grouping/aggregating: a plain `foreach`/`each` loop, a `var` map built with `|get:key:null` / `|set:key:value`, and a separate order-tracking array built with `array.push` — see `functions/ops/group_issues.xs` for the working pattern.
- **`mock` blocks inside a `db.get` or `db.query` action, submitted via `createFunction`, were rejected** (`"Syntax error: unexpected 'mock'"`) in this workspace, on two different db action types. Don't add inline `mock`/`test` blocks to a function pushed through this tool; verify real behaviour with `runWorkspaceFunction` instead (see below).
- **`redis.set` has no `as` clause** — `redis.set { ... } as $x` fails (`"Invalid arg: as"`); omit `as` entirely.
- **A multi-line boolean `where`/`precondition` expression (leading `&&`/`||` on its own line) failed to parse** (`"unexpected '&&'"`). Keep boolean conditions on **one line**, even when long.
- **Before pushing, use `getTableSchema`/`getFunction`/`getAPI` to fetch the live, current source** and diff against the local `.xs` file — the live workspace can drift from local files (phase-3 reserved table ids 74–79; ids 74–78 were already in use live by an unrelated initiative when checked in workspace 1).
- **`updateTableSchema` silently drops `validators`** (trim/lower/min-length) even when supplied in the documented shape — confirmed by two attempts with identical results. A `/feedback` bug report is already queued for this. Until fixed, re-adding lost validators needs the Xano dashboard UI directly, not this MCP tool.
- **After any push, run a real smoke test** with `runWorkspaceFunction` (functions) before trusting a success response from `createFunction`/`updateFunction`/`createAPI` — a clean push with no parse error does NOT mean the logic is correct; several of the above only surfaced once real (non-empty) data flowed through.

## Architecture rules (short form)
- Three layers: Definition (journey map and versions) → Commitment (plan) → Record (append-only log).
- Reference, do not copy. Tasks read their definition from the pinned map version.
- Statuses are fixed (`not_started`, `in_progress`, `blocked`, `done`, `skipped`); stages are dynamic.
- Variance is computed by the system; performers never report it.
- Two different actions use "publish": **Publish version** (map) and **Publish to live** (plan). Always use the full label.
- The UI helps; the server always validates again. Keep the user's typing on any rejected save.

## How to report back
- What was built, in one or two sentences.
- Which tests pass or fail (list failures with their ID).
- Anything that differs from the epic, and why.
- What is next, and any decision needed from the founder.

## Model guidance (tell the founder when to switch)

The AI cannot switch models itself; the founder runs `/model`. So:
- **At the start of every epic**, look up its model in the "Model" column of `product/stories/phase-4/README.md` and tell the founder in one line which model to use and why.
- **If the current model doesn't match**, say so **before writing any code** and wait for the founder to switch or say "continue".
- **Before a story marked risky** (below), and **when a bug has failed twice**, recommend switching to Opus.
- **After finishing an Opus-marked epic**, recommend an Opus review pass before moving on.
- **For mechanical sub-tasks**, mention that Haiku can do them more cheaply.

| Use | Model | When |
|---|---|---|
| Default builder | Sonnet 5.5 | Most epics: tables, endpoints, UI, tests. The specs are detailed, so it doesn't need to invent much. |
| Risky parts and reviews | Opus 5.5 | Publish gate and versions (PUB-1), status engine and activity log (LOG-1), guards and tenancy (GOV-1), a review pass after each of those, and any bug that fails twice. |
| Mechanical work | Haiku 5.5 | Test fixtures, the junk-input list, renames, small doc updates. |

## Key places
| What | Where |
|---|---|
| Product vision and decisions | `product/emgramprd.md` |
| Build order, tables, test conventions | `product/stories/phase-4/README.md` |
| Epics (one file per feature) | `product/stories/phase-4/EPIC-*.md` |
| Planner backend epics (phase 3) | `product/stories/phase-3/` |
| Table definitions | `static/tables/*.xs` |
| Journey-map APIs | `apis/journey_map/` |
| Journey-map app and unit tests | `webapp/protype-2/` |
| Planner app | `webapp/planningFrontendv2/` |
| Backend workflow tests | `workflow_tests/` |
