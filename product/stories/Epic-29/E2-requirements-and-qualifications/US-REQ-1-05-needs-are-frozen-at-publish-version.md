# US-REQ-1-05 — Needs are frozen at Publish version

**Epic:** REQ-1 · **Size:** M · **Model:** **Opus 5.5** · **Status:** ✅ Built (2026-11-26); one open item: remove frozen needs on a map hard delete
**Depends on:** story 04 · **Touches:** Publish version (PUB-1, endpoint 201). Ask before pushing.

## Description

A job reads everything about its steps from the map version it is pinned to. That is what stops
an edit to the map from changing work already in flight. Needs must follow the same rule, or a
designer changing "hard" to "soft" on a Tuesday would silently change who is allowed to do
Tuesday's live work.

So Publish version freezes the needs along with everything else. They are frozen into their own
small table keyed by the version, **not** into the version's snapshot. The snapshot has a content
hash that the frontend must reproduce byte for byte; adding to it would change the format and
risk every stored hash. A side table leaves every existing version untouched.

This story also adds the one function everything else uses to answer "what does this step need?"

## User story

**As** a planner, **I want** a job's needs to be the ones that were published with its map
version, **so that** an edit to the map never changes work already planned.

## Acceptance criteria

```gherkin
Scenario: publish freezes needs
  Given a step with one hard and one soft need
  When I Publish version
  Then the new version holds both, by stage key and row key

Scenario: a later edit does not reach the version
  When I then remove the hard need from the map and do not publish
  Then the published version still has it

Scenario: a new version carries the edit
  When I Publish version again
  Then the newer version does not have it, and the older version still does

Scenario: a job reads its own version
  Given a job pinned to the older version
  Then its step still needs the hard requirement

Scenario: a version published before this feature
  Then it has no needs, and its jobs behave as they do today

Scenario: a map with no needs
  Then Publish version produces the same hash it would have produced before this story

Scenario: every existing version still verifies
  Then verify_version passes for all of them, before and after

Scenario: an archived requirement at publish time
  Then it is frozen as set; archiving stops new use, it does not rewrite a map

Scenario: publish fails partway
  Then neither the version nor its needs exist

Scenario: the frozen needs cannot be edited
  Then no endpoint updates or deletes them; a hard-deleted map removes them with its versions

Scenario: one question, one answer
  When any code asks what a job's step needs
  Then it calls one function, which reads the job's pinned version
```

- The publish result and the version history screen show how many needs were frozen.
- **Tamper evidence:** each version stores a hash of its frozen needs (built by fixed-order
  concatenation, never through a JSON encoder), checked by the same nightly audit that checks the
  snapshot.

## Counter-measures

| Risk | Prevention |
|---|---|
| The content hash of existing versions changes | The snapshot and `pub/canonical_hash` are not touched. Test: hash every existing version before and after on a clone |
| Needs are written outside the publish transaction and a version exists without them | Written inside endpoint 201's existing `db.transaction`, as plain database writes |
| Two overlapping publishes freeze two sets under one version | The unique index (version, stage key, row key, requirement) plus the version's own existing race guard |
| The frozen rows are copied by cell id and break when a cell is recreated | Frozen by stage key and row key, which never change after creation, the same keys a job's step uses |
| A step's needs are read from the live map by mistake somewhere | One function, `req/step_needs`; a build guard (GUARD-1 style) fails if any other file queries the two need tables |
| The needs hash is built with a JSON encoder and never matches | Explicit concatenation in fixed order (sorted by stage key, row key, requirement id), `::` as the separator, never the pipe character |
| A version with no needs stores an empty hash that reads as "missing" | A fixed hash for "no needs", pinned in a test on both sides |
| A clone of the test map is skipped and the real map is used | Tests run on a clone of map 178, never the original |
| Hard-deleting a map leaves frozen needs behind | Added to `journey/delete_map_cascade` |

## Governance

- **Errors:** none new for the user; a failure is Publish version's existing "rolled back" error.
- **Events:** Publish version's existing success event gains `needs_frozen: n`. The nightly audit records a failure event for any version whose needs hash does not match.
- **Delete behaviour:** never deleted on their own; removed only with a hard-deleted map.

## Tests (write first)

| ID | Test |
|---|---|
| T-REQ-05-1 | Publish freezes hard and soft needs by key |
| T-REQ-05-2 | Draft edit does not reach a published version |
| T-REQ-05-3 | Two versions hold different needs |
| T-REQ-05-4 | A job on the older version reads the older needs |
| T-REQ-05-5 | A map with no needs: hash equal to the pre-story hash (pinned) |
| T-REQ-05-6 | Every existing version verifies before and after (on a clone) |
| T-REQ-05-7 | Forced failure leaves no version and no needs |
| T-REQ-05-8 | Needs hash matches the TypeScript twin; "no needs" hash pinned |
| T-REQ-05-9 | Build guard: only `req/step_needs` reads the need tables |
| T-REQ-05-10 | Hard delete of a map removes frozen needs |

## Keep a pulse on

- **This is why relaxing a rule does not unstick a job in flight** (README F-9). The design is right; the consequence needs decision D-10 (MATCH-1 story 06).
- After this epic, recommend an Opus review of the change to endpoint 201 before MATCH-1 starts.
