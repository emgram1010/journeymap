# VAL-1 — Input Validation and Friendly Errors

**Epic ID:** VAL-1
**Feature:** Junk never reaches the database, and when something is wrong the user is told clearly how to fix it.
**Status:** Planning
**Depends on:** OBS-1 (error catalog and events)
**Goal:** One shared set of field rules is applied **in the UI (to help the user) and again on the server (to protect the data)**. Rejections use plain language, keep what the user typed, say exactly what to change, and carry a Reference for support.

---

## MVP scope (after review, 2026-10-12)

All stories are in the MVP. Story 06 covers only the forms of MVP epics; rules for deferred features (roles registry, blocks, bulk publish, stage aggregates) are added when those features are built.

## Principle

**The UI is a convenience; the API is the guard.** The UI validates so people get instant, friendly help. The server always validates again, because anything can call the API.

## What counts as junk (rules applied to text)

- Empty or whitespace-only values for required fields.
- Control and zero-width characters; leading/trailing/multiple spaces (normalised, not rejected).
- Over-length values (each field has a maximum).
- HTML or script fragments in names and titles.
- Values outside an allowed set (not in the enum or not in the picker's list).
- Numbers that are not numbers, negative where not allowed, out of range, or fractional where whole numbers are required.
- Dates and times that are not valid, or inverted ranges (end before start).
- Duplicates of a name that must be unique ("already exists", with a pointer to the existing one).
- References to something that does not exist, was archived, or belongs to another account.

## Existing Architecture (Do Not Break)

- Existing cell/stage/map endpoints and their current validation. New rules are additive; legacy payloads that are valid today stay valid.
- The OBS-1 error catalog is the only place messages live.

## Non-Goals

- No spell-checking or AI content moderation. No rewriting of existing data.

---

## Stories

### US-VAL-1-01 — Field rules registry

**File:** `webapp/protype-2/src/validation/fieldRules.json` (read by the backend too)

- One entry per field that new phase-4 screens or endpoints accept: `entity.field`, label, type, required, min/max length or range, allowed values or pattern, normaliser, and the catalog error codes for each failure.

**Acceptance:** every input of every phase-4 endpoint has a rule (a test enumerates endpoints and fails on a missing rule).

### US-VAL-1-02 — Shared validators (frontend and backend)

**Files:** `webapp/protype-2/src/validation/validate.ts`, `functions/validate_field.xs`

- `normalize(value, rule)` and `validate(value, rule)` with identical behaviour on both sides, proved by golden fixtures.

**Acceptance:** the same fixtures produce the same results in both implementations.

### US-VAL-1-03 — Standard error response

- Every rejection returns `{ code, field, message, reference }` (HTTP 422 for validation, 403 for permission, 409 for conflicts and stale writes). `message` comes from the catalog; `reference` is the correlation id; no stack traces or internal names.

**Acceptance:** all phase-4 endpoints return this shape; a lint test checks error responses.

### US-VAL-1-04 — UI components and behaviour

**Files:** `webapp/protype-2/src/validation/FieldError.tsx`, `ErrorBanner.tsx`, `useFormValidation.ts`

- Inline message under the field, a summary banner at the top for several errors, the submit button disabled while invalid with a hint why, **user input preserved** on a rejected save, a visible Reference on unexpected errors, friendly states for "no connection", "you don't have access", and "someone else changed this".

**Acceptance:** no form clears the user's typing on error; no raw error text is shown.

### US-VAL-1-05 — Message style guide

**File:** `docs/error-message-style.md`

- Say what happened, say how to fix it, no jargon, never blame the user, one sentence where possible, keep the code out of the main text.

**Acceptance:** catalog lint (OBS-1) enforces length and banned words.

### US-VAL-1-06 — Applied to each epic's forms

- A checklist per epic of the forms and endpoints covered (role, stage, template, instance, job and attributes, tweak, publish to live, performer actions, variance filters).

**Acceptance:** the checklist is complete and each item links to its rule entries.

---

## Test Plan

**Junk corpus** (`validation/junk-corpus.json`): empty, spaces only, tab/newline, null character, zero-width space, 10,000 characters, `<script>alert(1)</script>`, `<b>bold</b>`, SQL-looking text (stored as plain text, never executed), emoji, very long single word, negative numbers, `NaN`, `1e999`, `"12abc"`, `0`, decimals, invalid dates (`2026-02-31`), inverted ranges.

| ID | Level | Case | Expected |
|---|---|---|---|
| UT-VAL-1-01 | Unit | `normalize` collapses spaces, strips control and zero-width characters | Cleaned value |
| UT-VAL-1-02 | Unit | Required field with each empty/whitespace case | Rejected with the field's catalog code |
| UT-VAL-1-03 | Unit | Over-length by one character | Rejected; exact limit accepted |
| UT-VAL-1-04 | Unit | HTML in a name | Rejected |
| UT-VAL-1-05 | Unit | Enum: valid and invalid | Accepted / rejected |
| UT-VAL-1-06 | Unit | Integer rules: 0, -1, 1.5, "abc", `1e999` | Per rule |
| UT-VAL-1-07 | Unit | Time `HH:MM` and date validity incl. leap day | Correct |
| UT-VAL-1-08 | Unit | Every rule's error code exists in the catalog | Pass |
| UT-VAL-1-09 | Unit | Corpus run through every rule | No value that should be rejected passes |
| UT-VAL-1-10 | Unit | Same fixtures through frontend and backend implementation outputs (exported JSON) | Equal |
| FT-VAL-1-01 | Functional (`workflow_tests/27_validation.xs`) | Corpus posted to each phase-4 create/update endpoint | Rejected values: 422, standard shape, **nothing written** |
| FT-VAL-1-02 | Functional | Valid but untrimmed input | Stored normalised |
| FT-VAL-1-03 | Functional | Duplicate name | 409/422 with friendly message and pointer |
| FT-VAL-1-04 | Functional | Reference to archived or foreign-account entity | Rejected |
| FT-VAL-1-05 | Functional | Response lint: no stack traces, no internal table names | Pass |
| FT-VAL-1-06 | Functional | Endpoint inventory vs. rules registry | Every input has a rule |
| FT-VAL-1-07 | Functional | Rejections appear as `rejected` events with code and reference | Yes |
| E2E-VAL-1-01 | UI | Submit empty required field | Inline message, button hint, input preserved |
| E2E-VAL-1-02 | UI | Server rejects (forced) | Friendly message with Reference; typing preserved |
| E2E-VAL-1-03 | UI | Stale-write conflict | "Someone else changed this" with reload action |
| E2E-VAL-1-04 | UI | Offline | "Connection required" message |

**Completion gate:** all pass; existing forms behave as before.

## Test Results

**2026-10-13 — Sonnet 5 build pass. Built, pushed to Xano workspace 1, smoke-tested.**

### Done and verified

| Story | State | Evidence |
|---|---|---|
| 01 field rules registry | ✅ | `fieldRules.json`/`.ts`. Entries for `ops_event.*` and `feature_flag.*` only — see `docs/val-1-coverage.md` for the rest, deferred to their owning epics. |
| 02 shared validators | ✅ live | `validate.ts` (frontend) + `validate_field.xs` (82, backend). 8/8 golden-fixture cases confirmed to match exactly via `runWorkspaceFunction`. |
| 03 standard error response | ✅ (frontend shape + lint) | `errorResponse.ts`: `{code, field, message, reference}` + leak lint. Backend side is the existing pattern (code embedded in the `inputerror` message, correlation id as `.reference` on `XanoHttpError`) — see the deviation note below. |
| 04 UI components | ✅ (untested by render) | `FieldError.tsx`, `ErrorBanner.tsx`, `useFormValidation.ts` + pure `formValidation.ts` (fully unit tested). No DOM/render-testing setup in this repo, so the components themselves are inspected, not rendered in a test. |
| 05 message style guide | ✅ | `docs/error-message-style.md` |
| 06 applied to each epic's forms | ✅ for what exists | `docs/val-1-coverage.md`. Role/stage/template/job/tweak/publish-to-live/performer/variance forms don't exist yet — same sequencing finding as GOV-1. |

**Live proof:** `ops/feature_flag` (516) replaces GOV-1's manual `addTableContent` workaround with a real, validated, admin-gated write — built entirely from already-proven pieces (`validate_field`, `require_platform_admin`, GOV-1's db patterns).

### Real bugs found and fixed before/during the push

1. **`max_length`/`min_value`/`max_value` are optional ints**, which arrive as `0` (not `null`) when omitted — the exact same class of bug as OBS-1's heartbeat. Caught **before** the live push this time (by reasoning from the prior incident), fixed with explicit `has_max_length`/`has_min_value`/`has_max_value` flags rather than a null check.
2. **`regex_matches` takes the pattern as the base and the subject as the argument** (`"/pattern/"|regex_matches:$value`), backwards from my first draft. Caught before pushing by reading the doc example closely after the first guess felt uncertain.
3. Both added to `CLAUDE.md`'s verified-constraints list.

### Deviation from the epic, deliberate

US-VAL-1-03 asked for a server-returned JSON body of exactly `{code, field, message, reference}`. **Not built that way.** Xano's `precondition`/`throw` only support a single `error` string + `error_type` (confirmed across OBS-1 and GOV-1); there's no way discovered yet to return arbitrary structured JSON on a thrown error. Used the pattern already proven and already live: the message carries `"... (E-VAL-004)"`, and `xano.ts`'s `XanoHttpError.reference` already carries the correlation id client-side. `errorResponse.ts` exists so the **shape itself** is tested and ready, and so a frontend catch-block can assemble the standard object by parsing the embedded code out of the thrown message — a small adapter, not yet written, since nothing calls `ops/feature_flag` from the UI yet.

### Not verified: `ops/feature_flag`'s own assembly

Pushed with no parse error; every piece it calls is independently proven. But there is no tool available in this session that can make a real authenticated HTTP call, and making any account platform-admin to work around that is explicitly the founder's decision, not mine to make unilaterally. Tracked in `product/learning-fixes.md`.

### Deferred — and why

All of US-VAL-1-06's remaining checklist rows (role, stage, template, job, tweak, publish-to-live, performer, variance forms) target screens/endpoints that **don't exist yet**. Same finding as GOV-1: validation rules land **with** the epic that builds the form, not retrofitted later. `docs/val-1-coverage.md` tracks each row against its owning epic so none is lost.
