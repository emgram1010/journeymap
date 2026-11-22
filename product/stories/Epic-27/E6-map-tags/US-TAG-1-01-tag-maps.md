# US-TAG-1-01 — Tag maps

**Epic:** TAG-1 · **Size:** S to M · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** the epic's "first check" (what `search_maps` already calls tags)

## Description

As the number of maps grows, the only grouping is the business they sit in and their parent.
There is no way to say "these six are operations" or "these are onboarding". A tag is the
lightest way to group: a short label, shared across the account, that can be put on any map
and taken off again without changing the map itself.

The risk with tags is sprawl: "ops", "Ops", "operations" and "Operation" as four tags that mean
one thing. This story stores each tag once per account and makes the AI reuse before it creates.

## User story

**As** the owner or an AI, **I want** to tag maps by area, **so that** related maps group together.

## Acceptance criteria

```gherkin
Scenario: tag a map
  When I add the tag "Ops" to a map
  Then the map has the tag "Ops"

Scenario: same tag, different case
  Given the tag "Ops" exists
  When I add "ops" or " OPS " to another map
  Then the existing tag is used and it still reads "Ops"

Scenario: a map has several tags, or none
  Then both are fine

Scenario: add the same tag twice
  Then the second add changes nothing and is not an error

Scenario: remove a tag
  Then the map loses it, and other maps keep it

Scenario: tagging does not touch the map
  Given a published map
  When I add or remove a tag
  Then no new version is created, no cell changes, and the published hash is the same

Scenario: clone a map
  When clone_scenario copies a map
  Then the copy has the same tags

Scenario: a bad tag name
  When the name is empty, longer than 40 characters, or contains HTML
  Then it is refused with a message that says why, and what I typed is kept

Scenario: too many
  When a map already has 20 tags, or the account has 200
  Then the next one is refused with the limit in the message

Scenario: rename a tag
  When I rename "Ops" to "Operations"
  Then every map that had it shows "Operations"

Scenario: delete a tag in use
  Then I am told how many maps use it and asked to confirm; the maps themselves are untouched

Scenario: an AI adds a tag that looks like an existing one
  When an AI asks to create "operations" and "Operations team" already exists
  Then the tool returns the close matches and creates nothing unless called again with create_new true

Scenario: another account
  Then it cannot see, use or change my tags
```

- Two new tables (additive): `map_tag` (account, name as shown, name key in lower case) with a
  unique index on (account, name key); `journey_map_tag` (map, tag) with a unique index on the pair.
- Tools: `tag_map` and `untag_map`, both through `journey/tool_gate` as writes, with a declared action type.
- **Assumed:** a small tag editor on the map's settings screen. The frontend was not read.

## Counter-measures

| Risk | Prevention |
|---|---|
| Two requests create "ops" at the same moment | The unique index on (account, name key) decides; the loser reads the winner's row |
| The lower-case key is done by a column filter that a later schema change drops | Compute the key in one function and store it; do not rely on a `filters=lower` column |
| Tags leak into the published snapshot and change stored hashes | A test publishes, tags, and compares hash and version count. Check `pub/build_map_snapshot` does not read the new tables |
| Editing a tag on a locked or published map is blocked by the map's write guards | Tagging uses its own check (may this caller edit this map's settings), not the cell-write path |
| A map with tags is deleted or archived and leaves links behind | Hard delete removes its links (query, loop by id, in a transaction). Archive keeps them, so restore brings them back |
| A tag delete removes only the first link | `db.del` by field touches one row. Query the links, then loop by id, in a transaction; re-query to confirm zero |
| A tag is used as an HTML injection point | VAL-1's field validation; shown escaped everywhere |
| Sprawl through near-duplicates | The reuse-before-create step for AI callers; the owner's rename merges into an existing tag when the new name already exists (asks first) |
| A second "tags" concept next to an existing one | The epic's first check; stop and ask if one exists |
| The clone copies tags from another account | Clone runs inside one account; the copy step checks the tag's account |

## Governance

- **Errors (suggested):** `E-TAG-001` name empty or too long · `E-TAG-002` no HTML ·
  `E-TAG-003` map has 20 tags · `E-TAG-004` account has 200 tags · `E-TAG-005` tag not found.
- **Events:** `map_tag.created`, `.renamed`, `.deleted` (with map count), `map.tag_added`, `map.tag_removed`.
  Failures record a failure event.
- **Delete behaviour:** deleting a tag removes its links and nothing else; deleting a map removes its links.

## Tests (write first)

| ID | Test |
|---|---|
| T-TAG-01-1 | Add, list, remove |
| T-TAG-01-2 | "Ops", "ops", " OPS " are one tag |
| T-TAG-01-3 | Adding twice is a no-op |
| T-TAG-01-4 | Published map: version count and hash unchanged after tagging |
| T-TAG-01-5 | Clone copies tags |
| T-TAG-01-6 | Name rules and both limits |
| T-TAG-01-7 | Rename updates every map; rename onto an existing name asks to merge |
| T-TAG-01-8 | Delete in use removes every link (re-query) and no map |
| T-TAG-01-9 | Two parallel creates leave one tag |
| T-TAG-01-10 | Second account sees nothing |
| T-TAG-01-11 | AI near-match returns suggestions and creates nothing |
