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

## Model guidance
- Default model is fine for implementing well-specified epics.
- Suggest switching to a stronger model for: reconciling the overlap in PRD §8.6, reviewing the publish gate and immutable versions, the status engine and activity log, tenant isolation, or a bug that has failed twice.

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
