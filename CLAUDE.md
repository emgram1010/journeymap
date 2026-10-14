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
- **A `where` clause cannot call filter functions.** `where = ... >= (now|transform_timestamp:"24 hours ago":"UTC")` fails at runtime with `"Unable to locate func entry: transform_timestamp"`, because a where clause compiles to SQL. Compute the value into a `var` first and reference the plain variable in the where clause. The same filter works fine in a `var`. **This one failed silently**: the heartbeat task ran every 5 minutes for 8 hours writing nothing, and was only caught by comparing the table's row count against the rows that session had created.
- **`db.patch` (and almost certainly `db.del`) with `field_name`/`field_value` touches only the FIRST matching row, not every match.** There is no "patch/delete where" form. Confirmed live: PLN-5's bulk-visibility endpoint patched by `workspace_id` and flipped exactly one of six agents, returning success. **To write or delete many rows, `db.query` them first and loop, patching/deleting each by `id`, inside a `db.transaction`.** This silently half-applies otherwise — and in a delete cascade it would orphan every child after the first.
- **`|contains:` returns `false` for EVERY array**, whether the value is present or not, literal or variable (confirmed live across four combinations). It is a string-substring filter; on an array it is not just wrong, it is uselessly wrong in the direction that looks like "not found". `index_of` and `in_array` do not exist either. **To test array membership, loop with `foreach` and compare, or use `x in $arr` inside a `db.query` `where` clause** (which does work — it compiles to SQL). Note this makes `!($visited|contains:$x)` always true, so any such de-duplication or cycle guard is doing nothing.
- **`|get` with a VARIABLE key silently ignores its default argument.** `{}|get:"missing":0` returns `0`, but `{}|get:$k:0` returns **`null`** — the default is thrown away whenever the key is absent and the key came from a variable. (It works correctly when the key *does* exist.) This fails silently and produces plausible output: PLN-3's plan-list counts all came back `null` because a tally loop did `|get:$key:0` → null → `null + 1` → null. `functions/ops/group_issues.xs` only escapes this because it passes `:null` as its default anyway. **Either pre-seed every key you will look up (see `apis/planner/524_workspace_GET.xs`, which seeds each tally to 0 before counting) or check for null explicitly.** Never trust the default with a variable key.
- **A function's leading comment IS its `description` field — never write both.** Supplying a header comment *and* a `description = "..."` statement makes Xano concatenate them into one description and drop the statement on round-trip, so the local file stops matching live. Write the comment only. (`functions/guards/*.xs` and others still have both; their live descriptions are doubled. Harmless, but don't copy it.)
- **A token minted by `security.create_auth_token` via `runWorkspaceFunction` is rejected by the live API** (`"Invalid token."`) even though the call matches `auth/login` exactly. To get a real token for HTTP testing without handling a password: run `Getting Started Template/generate_magic_link` for the test user (writes a hashed one-time token, sends no email), then POST that plaintext token to `reset/magic-link-login` over real HTTP.
- **`foreach` binds with an inner `each as $x` block**, not inline: `foreach ($list) { each as $x { ... } }`. `foreach ($list as $x)` is a parse error.
- **`function.run` passes arguments as `input = {...}`**, not as bare `key = value` lines.
- **`db.query`'s `return = {type: "count"}` works and returns a plain int** — the right way to count without loading rows. `where = $db.t.col in $ids` (an array variable) also works, as does a `join` block.
- **Don't nest a pipe inside a filter argument.** `$map|get:($row.id|to_text):null` parses but fails at runtime with `"Invalid expression"`. Hoist the conversion into its own `var` and pass the plain variable. (Pipes inside a `response` object literal are fine.)
- **An optional `int` input arrives as `0` when omitted, never `null`** — same rule as optional text ("" not null), just easy to re-forget for numbers specifically because `0` is also a legitimate value. `$input.max_length != null` is never true, so a limit of 0 can't be told apart from "no limit." Pass an explicit `has_x` boolean flag alongside any optional numeric bound instead of checking for null. (VAL-1, `functions/validate_field.xs` — caught before pushing this time, by remembering the OBS-1 heartbeat incident.)
- **`regex_matches` takes the pattern as the base value and the subject as the argument, with slash delimiters**: `"/<[a-zA-Z][^>]*>/"|regex_matches:$value` — not the other way round. Confirmed from the doc's own example (`"/^a.*c$/"|regex_matches:"abbbbc"`).
- **`redis.set` has no `as` clause** — `redis.set { ... } as $x` fails (`"Invalid arg: as"`); omit `as` entirely.
- **A multi-line boolean `where`/`precondition` expression (leading `&&`/`||` on its own line) failed to parse** (`"unexpected '&&'"`). Keep boolean conditions on **one line**, even when long.
- **Before pushing, use `getTableSchema`/`getFunction`/`getAPI` to fetch the live, current source** and diff against the local `.xs` file — the live workspace can drift from local files (phase-3 reserved table ids 74–79; ids 74–78 were already in use live by an unrelated initiative when checked in workspace 1).
- **`updateTableSchema` silently drops `validators`** (trim/lower/min-length) even when supplied in the documented shape — confirmed by two attempts with identical results. A `/feedback` bug report is already queued for this. Until fixed, re-adding lost validators needs the Xano dashboard UI directly, not this MCP tool.
- **After any push, run a real smoke test** with `runWorkspaceFunction` (functions) before trusting a success response from `createFunction`/`updateFunction`/`createAPI` — a clean push with no parse error does NOT mean the logic is correct; several of the above only surfaced once real (non-empty) data flowed through.
- **The delete action is `db.del`, not `db.delete`** — `db.delete` fails (`"unexpected 'db.delete'"`). `db.del` takes no `as` (confirmed from the doc's own example, which deletes by `field_name`/`field_value` and does not return the deleted record). (STAGE-1, `functions/set_stage_owner.xs`.)
- **`updateTableSchema`'s validator-dropping bug (above) applies to ANY table with `filters=trim`/`lower` text columns, not just `user`/`event_log`** — confirmed a second time on `journey_stage`/`journey_lens` (STAGE-1). The standing workaround is the same: add a new 1:1 side table (`journey_stage_owner`, `journey_lens_planned_work`) instead of a column, exactly like `account_feature_flag` (GOV-1). Treat this as the default move for any new optional field on an existing table that has text validators, not a one-off.
- **An omitted optional `bool`/`text` input is indistinguishable from `false`/`""` using `$input` alone — this applies inside `tool` definitions too, not just `query`/`function`.** Found in `ai/tool/update_stage_contract.xs`: its "omit a field = keep existing value" logic checked `$input.field != null`, which is never true for an omitted optional text field, so every call that omitted a field was silently overwriting it with `""`. The fix is the same `$raw_input` technique used elsewhere, with a three-way split (omitted / explicit `null` / explicit value) via a sentinel default: `$raw_input|get:"field":"__absent__"`, then compare to the sentinel for "was it sent at all" and to `null` for "was it sent as null." Confirmed live with a scratch function before trusting it in real code (STAGE-1).
- **`db.query`'s `where` can reference a plain `var` computed earlier to make an optional filter conditional, including an OR-based "skip this filter" pattern**: `where = ($has_filter == false) || ($db.table.col == $input.x)` — confirmed working (STAGE-1, `functions/backfill_stage_owners.xs`), avoids branching the query itself into separate `conditional` blocks (which risks the `as` variable not being visible outside the branch).
- **A side-table workaround (GOV-1/STAGE-1's answer to the `updateTableSchema` validator bug) needs its own dedicated `GET` list endpoint, or the frontend silently never sees the data.** The plain `GET` list/bundle endpoint for the *original* table (e.g. `GET /journey_stage`) only ever queries that table's own columns — it does **not** join the side table, so a field like `owner_lens_id` (really living in `journey_stage_owner`) comes back as `undefined` forever, with no error, no matter how correct the write path is. Caught live (AUTH-1, 2026-10-14) only because the readiness UI depended on the value and stayed wrong after a full reload. Fix: add a small, no-filter `GET` endpoint for the side table itself (`journey_stage_owner`, `journey_lens_planned_work`) and merge it into the frontend's state with a dedicated fetch — same shape both times.
- **An untouched `decimal` column defaults to `0`, not `null`, in live data** — a generalization of the already-documented "omitted optional decimal/int arrives as 0" rule, but worse: this is the **stored value already in the database** for a row nobody has ever edited, not just an omitted-input quirk. Frontend logic that treats "is this value non-null" as "has this field been touched" is wrong for any decimal column — it will treat every never-edited row as if it had real data. Found in AUTH-1's `cellHasAnyContent` (treated `timeDurationValue != null` as proof of content; it's `0` by default on every cell, so it flagged every untouched work cell as partially filled). Use a real touched/empty text or JSON signal instead, never a decimal field's nullness.
- **`now` is a numeric ms timestamp on its own, but inside an object literal it is the magic `"now"` token instead.** `var $t { value = now }` gives `1791951821495` and `now|to_int` works, but `duration_ms: (now - $started_at)` **inside an object literal** parses fine and then fails at runtime with `"Not numeric."` — in that position `now` is the same token that `data = {created_at: "now"}` relies on. Compute elapsed time into vars first (`var $end { value = now|to_int }`, then subtract) and pass the plain variable, the same hoisting rule that `where` clauses need. (PUB-1, endpoint 201 — found on the first real publish, not at push time.)
- **`db.transaction` works, and an `as` variable assigned inside one IS readable outside it** — unlike the warning about `conditional` branches. Confirmed with a scratch function before restructuring endpoint 201, so `db.transaction { stack { db.patch ... as $x ... } }` then using `$x` in the response is safe. Keep `function.run` and HTTP calls OUT of the transaction: compute anything pure (hashes, next version numbers) before it and keep the block to plain database writes.
- **Hashing anything that has to match the frontend must not go through `json_encode`.** Key order, whitespace and unicode escaping differ between encoders, so two sides encoding "the same" object produce different bytes. Build the string by explicit concatenation in a fixed field order and hash that (`$out|sha256`). Verified byte-identical against the TypeScript twice (PUB-1, `pub/canonical_hash.xs` ↔ `versionHash.ts`). Pin the expected hash on **both** sides so drift fails a test instead of silently invalidating stored hashes.
- **Confirmed working filters this session:** `sha256`, `replace` (chainable: `|replace:"a":"b"|replace:"c":"d"`), `values` (object → array, safe to `foreach`), `count`, `trim`, `lower`, `to_int`, `to_text`, `join`. `|first` on a non-paged `return = {type:"list"}` also works (it is already used live in endpoint 201).
- **There is no exposed tool to RUN a `workflow_test`.** `runUnitTest` only accepts unit tests attached to a function/query/middleware and rejects a workflow-test id; no `runWorkflowTest` exists in the MCP surface. Workflow test files can be written and pushed (`createWorkflowTest`) but not executed from a session — so when an epic's completion gate depends on them, drive each assertion through `runWorkspaceFunction` instead and say plainly in Test Results that the file itself was never run.
- **An untouched `enum` column also defaults to `""`, not `null`, and `??` doesn't catch it.** Same family as the above: a never-touched `time_duration_unit` comes back as an empty string, and frontend fallback code written as `value ?? 'minutes'` only falls through on `null`/`undefined` — `""` sails through unchanged. The `<select>` then visually shows the first option ("minutes", the browser's default for an unmatched value) while the real state stays `""`, which gets silently saved and breaks anything downstream that expects a real unit. Use `value || 'minutes'` (or an explicit `=== ''` check) for any enum-backed dropdown with an empty-string default, not `??`.

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
