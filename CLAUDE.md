# Emgram — Instructions for AI sessions

## Start here
1. Read `product/emgramprd.md` §0 (orientation), §10 (settled decisions) and §13 (next steps).
2. For build work, read `product/stories/phase-4/README.md`, then the epic file you are working on.
3. Do not ask the founder to re-explain the vision. If something is unclear, check the PRD first, then ask **one** short question.

## About the founder
- Product manager, **not an engineer**, and the only support person. ADHD/INTP-leaning.
- Keep answers **short and scannable**: lead with the decision, ask **one clear question at a time**. The hard limits are in **Response format** below — they are not optional.
- Explain in plain language. No jargon, no walls of text.
- **Explain before writing.** If asked to explain or review, answer in chat; do not create or edit files until asked.
- Treat their statements as direction, not gospel: validate, refine, point out gaps, then ask.
- Their examples are **illustrations**. Design the generic pattern; never build for a literal example (no industry assumptions).

## 🔴 Response format — a hard cap, not a style note

The founder is ADHD/INTP and has asked for this **four times** across sessions.
"Short and scannable" kept being interpreted generously, so it is now countable.

**Every chat response obeys all of these, by default:**

| Rule | Limit |
|---|---|
| Top-level bullets | **7 max** |
| Lines per bullet | **1** (2 only if a number or a name won't fit) |
| Sub-bullets | **none** |
| Tables | **none unless asked**, or unless replacing >4 bullets |
| Preamble / closing summary | **none** — no "here's what I found", no recap of what was just said |
| Open questions | **1 max**, last, its own bullet |

**Then stop and offer:** one closing line naming the detail available
("say the word and I'll expand X"). Do not deliver it unasked.

**Applies hardest to** build reports, discovery write-ups, epic summaries and
"what did you do" answers — the exact cases where long-form is most tempting.

**What this does NOT mean:** fewer findings. Research still happens in full and a
real risk still gets a bullet. **Trim words, never substance.** If the content
genuinely cannot fit, say so in one bullet and offer the long version — do not
silently exceed the cap.

**Exception:** the founder explicitly asks for depth ("explain in detail", "walk
me through it", "give me the full write-up"). Documents written to files are not
chat and are not capped.

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
- **The MCP `updateTableContentItem` tool does NOT reliably patch a row — treat it as unusable.** Calling it with a single field (`{user_id: 9}`) on a `planner_agent` row also **reset that row's `workspace_id`**, moving the agent into a different plan; a follow-up call that supplied `workspace_id` explicitly did **not** put it back. Repaired with a scratch function using `db.patch`, which worked first time. **For any ad-hoc row edit, write a throwaway function with `db.patch` and run it with `runWorkspaceFunction`.** (LIVE-1, 2026-10-15. The tool's own description warns it is destructive; this is what that means.)
- **A `conditional` inside a `foreach` whose CONDITION reads a variable `var.update`d earlier in the same iteration silently discards everything the branch writes.** Proven live with three side-by-side tallies over identical data: condition on the loop item (`if ($r.flag == true)`) → correct; condition a constant (`if (true)`) → correct; condition on a var updated earlier in that same iteration (`if ($cur != null)`) → **every write in the branch lost, result all zeros, no error**. This is why `functions/ops/group_issues.xs` and PLN-3's list endpoint work (their conditions read the loop item) while PLN-6's first timeline list reported `task_count: 0` for every row. **Only branch on the loop item, on an input, or on a variable set before the loop started.** If you need to skip unknown keys, constrain the query instead so the skip is unnecessary — see `apis/planner/539_workspace_workspace_id_timeline_GET.xs`, which scopes its task query with `timeline_id in $tl_ids` precisely to avoid needing an `if`.
- **An omitted optional `date` input does not exist at all** — unlike `text`/`int`, which arrive as `""`/`0`. Referencing it fails at runtime with `"Unable to locate input: date_from"`. And on a **GET** there is no JSON body, so `util.get_raw_input|has:"x"` cannot detect it either. **Declare optional date filters as `text`** (they default to `""`, which is testable) and widen the bound to a sentinel like `"0001-01-01"` / `"9999-12-31"` when absent; comparing a text date against a `date` column in a `where` clause works.
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
- **Confirmed working filters this session:** `sha256`, `replace` (chainable: `|replace:"a":"b"|replace:"c":"d"`), `values` (object → array, safe to `foreach`), `count`, `trim`, `lower`, `to_int`, `to_text`, `join`. `|first` on a non-paged `return = {type:"list"}` also works (it is already used live in endpoint 201). **Also confirmed on real data (ORD-1, 2026-10-19):** `"/[^0-9]/"|regex_replace:"":$text` (pattern first, then replacement, then subject); `"/^s[0-9]+$/"|regex_matches:$text`; a **bool `|to_int`** gives 0/1, which lets you fold a test into arithmetic instead of a `conditional` inside a loop (see `functions/journey/next_stage_key.xs`); and `|max` on an array built with `array.push` works, unlike `[index]` on the same array. `$obj|has:"key"` exists and tells "present with value 0" from "absent" — the way to detect an optional int on a POST body (`util.get_raw_input` then `|has`), where `$input` can't. A `db.query ... return = {type: "single"}` that matches nothing gives a value that `|get:"id":0` safely turns into `0` (no crash), so a key→id lookup needs no `conditional` in the loop.
- **There is no exposed tool to RUN a `workflow_test`.** `runUnitTest` only accepts unit tests attached to a function/query/middleware and rejects a workflow-test id; no `runWorkflowTest` exists in the MCP surface. Workflow test files can be written and pushed (`createWorkflowTest`) but not executed from a session — so when an epic's completion gate depends on them, drive each assertion through `runWorkspaceFunction` instead and say plainly in Test Results that the file itself was never run.
- **A `|` character inside a STRING LITERAL breaks the parser.** `var $k { value = $a ~ "|" ~ $b }` fails at runtime with `"Invalid syntax. Try using the \"transform\" filter or an expression."` — the pipe is read as a filter separator even inside quotes. Changing the separator to `"::"` fixed it with no other edit. Don't build composite map keys, fingerprints or delimiters out of `|`; use `::`. (LOG-1, `scratch/verify_transitions`.)
- **Nested `foreach` works, and so does a `conditional` nested inside another `conditional`'s `else` branch.** Both confirmed live with real data: a 5×7 `foreach`-in-`foreach` walking every (status, event) pair through a `function.run`, and two-deep `if`/`else`/`if` in `functions/ops/audit_execution.xs`. Worth stating explicitly, because so many neighbouring constructs silently fail that it is tempting to avoid these too. (LOG-1.)
- **A `function.run` inside a `foreach` works, including one that itself runs a `db.query` per iteration.** `ops/audit_execution` replays every task through `log/replay_task` this way. Fine at MVP volumes for a nightly job; it is one query per row, so don't put this shape on a request path.
- **Put a shared RULE in its own function rather than copying it into the reader and the writer.** Not a syntax constraint — a house rule earned here. LOG-1's transition table started out duplicated between the record-event endpoint and the replay audit, which is the one duplication that matters: an audit holding its own copy of the rule it audits will eventually disagree with the engine and sound equally certain either way. Extracted to `log/next_status` (and `log/derive_job_status` out of `log/sync_job_status`), then verified by diffing all 35 live (status, event) pairs against the TypeScript twin.
- **An untouched `enum` column also defaults to `""`, not `null`, and `??` doesn't catch it.** Same family as the above: a never-touched `time_duration_unit` comes back as an empty string, and frontend fallback code written as `value ?? 'minutes'` only falls through on `null`/`undefined` — `""` sails through unchanged. The `<select>` then visually shows the first option ("minutes", the browser's default for an unmatched value) while the real state stays `""`, which gets silently saved and breaks anything downstream that expects a real unit. Use `value || 'minutes'` (or an explicit `=== ''` check) for any enum-backed dropdown with an empty-string default, not `??`.

## 🔴 CRITICAL: `db.patch` on a `json` column MERGES with the existing value — it does NOT replace it

Confirmed live, the hard way, during a security cleanup (2026-10-16):
`db.patch event_log { data = {metadata: {a: 99, d: 4}} }` against a row
whose `metadata` was already `{a: 1, b: 2, c: 3}` produced
**`{a: 99, b: 2, c: 3, d: 4}`** — `a` overwritten, `b`/`c` preserved from
before, `d` added. A shallow merge, exactly like `|set:` would do, not
a replace. This is DIFFERENT from every other column type confirmed
this project (text/int/enum/bool all fully replace) — it is specific
to `json`-typed columns.

**Why this is CRITICAL and not just worth-knowing:** a cleanup meant to
ERASE sensitive data from ~2,600 rows ran, reported success, incremented
its own counter correctly — and left every original key fully intact,
because it was merging a "safe" object on top of the dangerous one
instead of replacing it. The bug was caught only by re-querying and
checking, not by trusting the function's own reported counts.

**The fix: a TWO-STEP patch.** Patch the column to `null` first (there
is nothing to merge a new object INTO, so this one genuinely clears
it), then patch it again with the real value in a second call.
Confirmed live: `null` then `{d: 4}` on a column that was `{a,b,c}`
correctly yields exactly `{d: 4}`, nothing else.

**The rule going forward:** never trust a single `db.patch` to replace
a `json` column's content. If the intent is "this is now exactly X,"
two patches. If the intent is "merge X into whatever is there," one
patch is correct and this is a feature, not a bug — know which one you
mean before writing it.

## 🔴 CRITICAL, codebase-wide: `==`/`!=` against `null` use PHP-style loose equality — `0`, `""`, `false` and `[]` ALL equal `null`

Found building VAR-1 (2026-10-15), and almost certainly the explanation
behind several earlier "defensive-looking" double-checks in this
codebase that were never fully explained. Confirmed with a scratch
function testing every falsy type directly:

| expression | result |
|---|---|
| `0 == null` | **`true`** |
| `"" == null` | **`true`** |
| `false == null` | **`true`** |
| `[] == null` | **`true`** |
| `1 == null` | `false` (correct) |

**This means `$x == null` / `$x != null` is NEVER a safe way to ask "was
this really never set" for any field that can legitimately hold a
falsy value** (`0`, `""`, `false`, an empty array) — it is
indistinguishable from "this is genuinely zero/empty/false". The
engine is doing a PHP-style loose comparison, not a strict one.

**Why this hasn't caused visible damage everywhere already:** most
timestamp fields in this codebase hold real epoch milliseconds in
production (never legitimately `0`), and several existing call sites
already double-check defensively — e.g. `log/sync_job_status.xs`:
`if ($t.started_at != null && $t.started_at != 0 && ...)`. That second
condition was very likely added because `!= null` alone didn't behave
as expected, without the root cause being named. It is correct by
accident, not by understanding.

**The rule going forward:**
- Never test "was this set" with `== null`/`!= null` alone when the
  real value could legitimately be `0`, `""`, `false`, or `[]`.
- For numbers that could be a legitimate zero (a duration, a count), add
  an explicit `!= 0` alongside `!= null` — belt and suspenders, same
  shape as the existing `sync_job_status` line, but now written on
  purpose.
- For a value that is NEVER legitimately falsy in production (an epoch
  ms timestamp, a real id starting at 1), `== null` is safe in
  practice — but write a comment saying so, because a test fixture
  using `0` or small offsets as a stand-in timestamp WILL trip this
  (caught exactly that way: `variance/compute_task_variance` passed
  every golden case with realistic epoch timestamps and silently
  produced wrong output — "done without start", `actual_minutes: null`
  — the one time a smoke test used `occurred_at: 0`).
- **Never use `0` (or an offset from `0`) as a stand-in timestamp in a
  smoke test again.** Use a realistic epoch base (e.g. `1_800_000_000_000`)
  plus small minute offsets, exactly like the TypeScript golden
  fixtures already do.

**Not audited further here:** whether any OTHER existing endpoint
relies on an unguarded `== null`/`!= null` against a field that can
really be `0`/`""`/`false` in production data. That is a GOV-1-shaped
sweep of its own, flagged in `learning-fixes.md`, not done as part of
VAR-1.

## 🔴 Xano routing: a static path segment can be permanently shadowed by an earlier dynamic path in the same API group + verb

Found live building PLN-9 (2026-10-16): `GET journey_map/search` (endpoint
210, built for IL-01-04, meant to be an account-scoped published-map
search) 400s on **every single call** with `"Value is not a valid
integer." {"param":"journey_map_id"}` — a param that endpoint doesn't
even declare. Root cause: `GET journey_map/{journey_map_id}` (endpoint
23, built almost two months earlier in the same group) matches first,
and the literal segment `"search"` gets bound to `{journey_map_id}`
and fails its own `int` validator. Endpoint 210 has therefore been
dead code since the day it was created — it builds, it has no syntax
error, and it will never once execute.

**This is invisible from the endpoint's own source** — 210's XanoScript
is completely correct in isolation; the collision only exists against
a sibling endpoint elsewhere in the same group. `getAPI`/`getFunction`
diffing (already a standing rule below) does not catch this either,
since nothing about 210's own definition looks wrong.

**The rule going forward:** before adding a new **static** path
segment (`/foo/search`, `/foo/export`, `/foo/summary`, etc.) next to
an existing **dynamic** one (`/foo/{foo_id}`) in the same API group
and verb, check whether the dynamic route already exists — `listAPIs`
on that group and scan for the same leading segment. If it does, the
static one is unreachable unless Xano's router is confirmed to prefer
static paths (not verified here; assume it does not). The safe fix is
the one used elsewhere in this app when this exact shape showed up:
don't rely on a sub-path at all — use a different static prefix
(`/foo-search`) or fold the behavior into a query parameter on the
list endpoint instead. PLN-9 worked around it by using the plain
`GET journey_map` (no path param at all, so no collision) and filtering
client-side, with a known gap noted (owner-scoped, not account-scoped) —
not a fix to 210 itself, which still needs its own resolution later.

## Frontend constraints — verified live, APP-1 (2026-10-15)

- **`redis.ratelimit` / `redis.get` / `redis.set` are rejected outright on this Xano plan** with `403 "Not supported. Please upgrade your Xano instance."`, regardless of caller or input. `apis/ops/1_ops_event_POST.xs` (OBS-1) used all three and has therefore refused every call since it was built — rewritten to the same rate-limit/de-dup rule using a plain `db.query ... return = {type: "count"}` against `event_log` with a cutoff timestamp computed into a `var` first, instead. Before using ANY `redis.*` filter on this instance, confirm it works with a scratch function first; assume it does not.
- **Multiple API groups means multiple base URLs — a `fetch` to the wrong one 404s with no hint it picked the wrong group.** `webapp/protype-2/src/xano.ts`'s `getOpsHealth`/`getOpsIssues`/`getOpsBundle` and `ops/logEvent.ts`'s `defaultSend` were all calling `xanoRequest('/ops/...')`, which targets the journey-map group (`ER4MRRWZ`) — but `/ops/*` only exists in its own group ("Ops", canonical `-2MhtESP`, **note the required `:v1` suffix**: `api:-2MhtESP:v1`, confirmed from that group's own OpenAPI spec). Every Health-page read and every client-side event send had been hitting a 404 since OBS-1 was built. Fixed by adding an optional `baseUrl` to `xanoRequest`'s options and a `getXanoOpsBaseUrl()` constant, same pattern as the existing `getXanoAuthBaseUrl()`. **Before wiring a frontend call to a newly-pushed endpoint, confirm which `api_group` it actually lives in** (`listAPIGroups`) — don't assume the app's one existing base URL covers it.
- **A pipe chain immediately after a parenthesized `|get` expression is fine**: `($map|get:$key:0)|to_text` is NOT the "nested pipe inside a filter argument" trap (that trap is a pipe used as an ARGUMENT to another filter, e.g. `|get:($x|to_text):null`). Chaining a filter onto the result of a fully-parenthesized expression works. Confirmed live in `perform/hydrate_statuses`.
- **Excluding a list of ids in a `where` clause must be written `not in`, never `!(... in ...)`.** `where = ... && !($db.journey_map.id in $deleted_ids)` **pushes cleanly and then fails at runtime**, with no usable error message — the MCP tool just reports "Unable to get successful response". `where = ... && ($db.journey_map.id not in $deleted_ids)` works and compiles to SQL. Confirmed twice on a scratch function, after the broken form took down all three map-keyed journey-map list endpoints live and had to be reverted (SEC-1, `journey/visible_map_ids`, 2026-10-19). Positive `in` was already known to work; the negation is a separate fact. **Seed the exclusion array with a sentinel (`-1`) so it is never empty** — `not in [-1]` correctly excludes nothing (16 of 16 rows kept), while `not in []` is untested.
- **`int[]`/array-typed function inputs work and round-trip correctly** (`input { int[] work_task_ids }`, `input { int[] agent_ids }`), confirmed live via `runWorkspaceFunction` and real HTTP.

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
