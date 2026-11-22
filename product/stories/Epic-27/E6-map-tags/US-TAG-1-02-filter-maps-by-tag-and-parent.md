# US-TAG-1-02 — Filter maps by tag and parent

**Epic:** TAG-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-TAG-1-01

## Description

`list_maps` returns every map the caller can see, and an AI then reads the whole list to find
the few it needs. Parent maps already exist in the data (`parent_map_id`), but the tool cannot
filter by them and does not even return them. With tags from story 01, two small filters and
one new tool turn "scan 25 maps" into "read this branch".

## User story

**As** an AI, **I want** to list maps by tag and by parent, **so that** I read only the branch I need.

## Acceptance criteria

```gherkin
Scenario: no new filters
  When list_maps is called as it is today
  Then the same maps come back in the same order
  And each result now also has tags and parent_map_id (added fields only)

Scenario: filter by tag
  When list_maps is called with tag "ops"
  Then only maps tagged "Ops" are returned, whatever the case of the input

Scenario: filter by parent
  When list_maps is called with parent_map_id 210
  Then only maps whose parent is 210 are returned

Scenario: top-level maps
  When list_maps is called with top_level_only true
  Then only maps with no parent are returned

Scenario: combine filters
  When tag, parent_map_id and status are all given
  Then a map must match all of them

Scenario: unknown tag
  Then the result is an empty list, not an error

Scenario: a parent in another account, or one I cannot see
  Then the result is an empty list (never "not allowed")

Scenario: list the tags
  When list_tags is called
  Then each tag is returned with the number of maps I can see that carry it
  And tags with no visible maps show 0

Scenario: archived maps
  Then they are not counted and not listed, as today
```

- `parent_map_id` left out arrives as `0`, and `0` is also how "no parent" is stored. So "top
  level only" is its own boolean (`top_level_only`), never `parent_map_id: 0`.
- `list_tags` goes through the gate as a read and is scoped to the caller's account and, in a
  chat, to the chat's business.

## Counter-measures

| Risk | Prevention |
|---|---|
| Today's output changes | Capture `list_maps` output on the real account before the change; compare after, ignoring only the two added fields |
| The filter loop uses `!= null` on an int that is really `0` | Use explicit `!= 0` for `parent_map_id` and `!= ""` for `tag`; loose null equality treats 0 and "" as null |
| A flag updated earlier in the same loop pass loses its writes | Do the tag and parent filtering in the `where` clause (`id in $tagged_ids`, with the "skip this filter" OR pattern) so the loop needs no new branch |
| An empty id list in the `where` clause misbehaves | Seed the list with `-1`; an unknown tag then matches nothing |
| Array membership tested with `\|contains` (always false) | Use `in` inside the query, or a loop compare |
| Tag counts come back null | Seed every tag's count to 0 before counting |
| Tags per map cost one query per map | One query for all links of the listed maps (`journey_map_id in $ids`), then group in a loop |
| `list_tags` counts maps the caller cannot see | Count only within `journey/visible_map_ids` and the chat's business |
| A piped filter inside a longer condition swallows the rest | Lower-case and trim the tag input into a `var` first; no pipes inside the condition |
| The connector's tool list and the in-app copilot's list drift | Add `list_tags` to both; update `list_maps`' instructions text in the same push |

## Governance

- **Errors:** none new. Unknown tag and unseen parent both return an empty list.
- **Events:** the gate's tool-log row per call. A failed query records a failure event.
- **Friendly message** in the tool text: "An unknown tag returns an empty list. Call list_tags to see the tags that exist."

## Tests (write first)

| ID | Test |
|---|---|
| T-TAG-02-1 | No filters: output identical to before, plus the two new fields |
| T-TAG-02-2 | Tag filter, any case |
| T-TAG-02-3 | Parent filter; `top_level_only` |
| T-TAG-02-4 | Combined filters are AND |
| T-TAG-02-5 | Unknown tag gives an empty list |
| T-TAG-02-6 | Parent in another account gives an empty list |
| T-TAG-02-7 | `list_tags` counts match a hand count; a tag with no visible maps shows 0 |
| T-TAG-02-8 | Archived maps are neither listed nor counted |
| T-TAG-02-9 | Second account sees none of the first account's tags or counts |
