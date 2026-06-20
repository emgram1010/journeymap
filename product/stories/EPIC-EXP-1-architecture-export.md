# Architecture-Aware Journey Map Export — Epic PRD

**Epic ID:** EXP-1
**Status:** Planning
**Goal:** From a single journey map tile, export that map as the root plus every reachable sub / exception / anti-journey / ai-agent-manual map into one Markdown bundle whose files are self-explanatory to humans and LLMs (NotebookLM in particular).

---

## Context

Three single-map exporters exist today:

| File | Output |
|---|---|
| `static/src/exportMarkdown.ts` | One `.md` per map |
| `static/src/exportMarkdownBundle.ts` | ZIP with `AGENTS.md`, metadata, actors, stages, matrix-grid, per-stage files |
| `static/src/exportMarkdownNotebookLM.ts` | NotebookLM-optimized MD with 500K-word guard |
| `static/src/exportArchitectureNotebookLM.ts` | Flat: every map in the architecture, no link traversal, no parent refs |

The flat architecture export strips the `journey_link` graph. An LLM reading those sources cannot answer "what triggers the recovery map?" because the origin cell, parent stage, and parent actor are gone.

The journey-map data model already supports the relationships we need to surface:
- `journey_link (source_map, source_cell, target_map, link_type)` — `exception | anti_journey | sub_journey`
- `journey_lens.agent_map_id` — ai_agent lens points to its operating-manual sub-map
- `journey_map.parent_map_id` + `map_level` — L1 / L2 / L3 hierarchy

---

## Existing Architecture (Do Not Break)

- `tables/14_journey_link.xs` — unique on `(source_cell, target_map)`
- `tables/6_journey_map.xs` — `parent_map_id`, `map_level`
- `tables/8_journey_lens.xs` — `agent_map_id`, `actor_type`, persona / goal / constraints
- `tables/9_journey_cell.xs` — `content`, `actor_fields`, duration fields
- `apis/journey_map/75_journey_link_GET.xs` — link list, owner-scoped
- `tools/55_publish_map.xs` — already walks `journey_link` at publish time to compile the automation snapshot graph; reuse the same traversal pattern
- `static/src/exportMarkdownBundle.ts::buildJourneyMapFiles` — per-map MD builder; reuse, do not duplicate
- `static/src/ArchitectureDetail.tsx` — `MapTile` component, lines ~88 onward, holds the per-tile `…` menu where the new action lands

---

## Non-Goals

- No architecture-level "export everything" button in this epic — per-tile entrypoint only.
- No change to the existing three single-map exporters.
- No PDF / DOCX output.
- No incremental sync to NotebookLM (one-shot export only).
- No cross-architecture traversal — warn and stop at the boundary.

---

## Output Shape

```
{root-map-slug}/
├── ARCHITECTURE.md              entrypoint: map index (Mermaid inline only if opted-in — US-EXP-1-09)
├── GLOSSARY.md                  anchor scheme + lens / link-type primer
├── _manifest.json               machine-readable: maps[], links[], word_counts, warnings
└── maps/
    ├── 01-{root-slug}/
    │   ├── README.md            summary + origin block ("(root)")
    │   ├── 00-metadata.md
    │   ├── 01-actors.md
    │   ├── 02-stages.md
    │   ├── 03-matrix-grid.md
    │   ├── 04-outbound-links.md only when the map has outbound links
    │   └── stages/s{N}-*.md     per-stage; cells anchoring links get a callout
    ├── 02-{sub-map-slug}/
    │   └── …
    └── …
```

Folder numbering follows BFS from the root so the order is stable and deterministic.

---

## Stable Anchor Scheme

Every entity in the bundle gets a deterministic ID, repeated everywhere it is referenced:

```
[MAP:m126-linkedin-outreach]
[STAGE:m126/s1-send-connection-request]
[LENS:m126/l3-handoff]
[CELL:m126/s1×l3]
[LINK:m126/s2×l3 →exception→ m127]
```

Format: `[TYPE:map-id-slug/local-key]`. Slugs are derived from `journey_map.id` + title slug, `journey_stage.key`, `journey_lens.key`. Two exports of the same architecture produce byte-identical anchors.

---

## Origin Block (every non-root map)

Each non-root `README.md` opens with YAML frontmatter + prose callout:

```markdown
---
map_id: m127
title: Connection Request Declined — Recovery
link_type: exception
parent_map:   [MAP:m126-linkedin-outreach]
parent_stage: [STAGE:m126/s2-await-response] "Await Response"
parent_lens:  [LENS:m126/l3-handoff] (handoff actor)
parent_cell:  [CELL:m126/s2×l3]
parent_actor_persona: "SDR handing off declined invites for warm follow-up"
---

> **Origin.** This map handles the `exception` path triggered at
> [CELL:m126/s2×l3] in [MAP:m126-linkedin-outreach]. The parent cell
> says: "Prospect declines or ignores after 14 days." When that
> condition fires, the runtime follows this map.
```

The parent cell `content`, parent stage `stage_goal`, and parent lens `persona_description` + `primary_goal` are inlined verbatim so the sub-map is self-explanatory in isolation.

---

## Traversal Rules

Starting from the user-selected root map:

| Edge | Included | Notes |
|---|---|---|
| `journey_link` where `source_map = X`, any link_type | ✅ recursively | |
| `journey_lens.agent_map_id` on any lens of X | ✅ recursively | Synthesized `link_type = agent_manual` |
| `journey_map.parent_map_id = X` (children) | ✅ recursively (configurable) | Default on |
| Cycle A → B → A | Detected | Mark `[CYCLE]`, do not re-expand |
| Target outside architecture | Skipped | Recorded in `_manifest.json.warnings` |

Depth cap config (default 5). Word-budget guard: if total > 500K words, return a `split_plan` instead of silently truncating.

---

## User Stories

---

### US-EXP-1-01 — Architecture graph walker endpoint

**Story:** As the exporter, I need a backend endpoint that, given a `root_map_id`, returns every reachable map and link in one round trip.

**Endpoint:** `GET /journey_map/{root_map_id}/export/linked_graph`
**Auth:** `user` (owner-scoped)
**Query:** `max_depth?` (default 5), `include_agent_manuals?` (default true), `include_children?` (default true)

**Response:**
```json
{
  "root_map_id": 126,
  "maps":  [ { /* HydratedJourneyMapBundle per map */ } ],
  "links": [ { /* journey_link rows */ } ],
  "warnings": [ { "type": "cycle|cross_arch|depth_cap", "detail": "…" } ]
}
```

**Acceptance:**
- Walks `journey_link`, `journey_lens.agent_map_id`, and `journey_map.parent_map_id` per the traversal rules.
- Cycle detection: each map visited at most once; offending edge recorded in `warnings`.
- Cross-architecture targets skipped and recorded.
- Tenant-scoped via existing `owner_user` filter (same pattern as `get_map`).
- Single graph traversal — no N+1 round-trips per node.

---

### US-EXP-1-02 — Word-budget pre-flight

**Story:** As the exporter, I want word-count estimates per map and a total so I can warn or refuse export before zipping.

**Acceptance:**
- Endpoint response includes `word_count` per map and `total_word_count`.
- When `total_word_count > 500_000`, response also includes `split_plan: [{ root_map_id, included_maps[], word_count }]` proposing sub-trees that each fit.
- Word counting reuses the helper in `exportMarkdownNotebookLM.ts` (`countWords`).

---

### US-EXP-1-03 — Canonical anchor scheme

**Story:** As an LLM consuming the bundle, I want every map / stage / lens / cell / link to have a deterministic slug-based ID that resolves across separately-retrieved chunks.

**Acceptance:**
- Anchor format exactly as specified above.
- Map slug = `m{id}-{title-slug}`; stage local = `s{N}-{label-slug}`; lens local = `l{N}-{label-slug}`; cell = `s{N}×l{N}`.
- Anchor grammar documented in `GLOSSARY.md` (US-EXP-1-08).
- Two exports of the same architecture produce byte-identical anchors.

---

### US-EXP-1-04 — Origin block on non-root maps

**Story:** As a reader opening a sub / exception / anti-journey / agent-manual map in isolation, I want the README to begin with a frontmatter + prose block that names the parent map, stage, lens, cell and inlines the parent cell content.

**Acceptance:**
- Block format matches the spec above (YAML frontmatter + `> Origin.` callout).
- Inlined fields: parent cell `content`, parent stage `stage_goal`, parent lens `persona_description`, parent lens `primary_goal`.
- `link_type` is one of `sub_journey | exception | anti_journey | agent_manual` (the last synthesized for `agent_map_id` edges).
- Root map's README has a placeholder origin block with `link_type: root` and no parent fields.

---

### US-EXP-1-05 — Outbound-links file on parent maps

**Story:** As a reader, I want every parent map to include `04-outbound-links.md` listing every cell that branches to another map so the graph is navigable in both directions.

**Acceptance:**
- Table columns: cell anchor, link type, target map anchor, label / "why" (uses `journey_link.label` if set, else falls back to parent cell content excerpt).
- File omitted when the map has no outbound links.
- File is referenced from the map's `README.md`.

---

### US-EXP-1-06 — Inline link callouts in per-stage files

**Story:** As a reader looking at a single per-stage file, I want any cell anchoring a link to surface a callout pointing to the target map so I don't have to consult the outbound-links file separately.

**Acceptance:**
- Callout format: `> 🔗 **Branches to** [MAP:…] (`link_type`). See `maps/NN-…/README.md`.`
- One callout per link, placed immediately under the cell heading.
- Applies to all four link types including `agent_manual`.

---

### US-EXP-1-07 — Architecture entrypoint (map index)

**Story:** As a reader opening the bundle for the first time, I want `ARCHITECTURE.md` to list every map with title + summary so I can orient before drilling in.

**Acceptance:**
- Map list ordered root → BFS, matching the `maps/NN-…` folder numbering.
- Each row: anchor, title, `map_level`, reachable-from-root depth, link type from parent (root for the first row), one-line summary.
- Cycle markers shown in the table when present (`⟳ cycles back to [MAP:…]`).
- Mermaid diagram is **not** part of this story — see US-EXP-1-13.

---

### US-EXP-1-08 — Glossary primer

**Story:** As an LLM with no prior context, I want `GLOSSARY.md` to define lens / stage / cell / actor / link types and the anchor scheme so the model has the vocabulary needed to answer correctly.

**Acceptance:**
- Sections: anchor grammar, link-type semantics, actor-type catalog, cell-status meanings, plan-vs-actual semantics.
- ≤ 800 words.
- Anchor examples in the glossary use the same map IDs that appear elsewhere in the bundle (no fictional samples).

---

### US-EXP-1-09 — "Linked bundle…" dialog with scope picker

**Story:** As a user opening the **Export ▸ Linked bundle…** action on a map tile, I want a dialog that lets me choose what to include (all linked, sub-journeys only, exceptions only, or parent only) before downloading.

**Acceptance:**
- Dialog header shows the root map title, `map_level`, and `m{id}`.
- Scope radio group with four mutually-exclusive options, each showing live counts `{map count} · {word count} · {fit badge}`:
  - `Parent + all linked` (default) — sub_journey + exception + anti_journey + agent_manual edges.
  - `Parent + sub-journeys only` — `link_type = sub_journey` and `agent_map_id` edges.
  - `Parent + exceptions only` — `link_type = exception`.
  - `Parent only` — single-map; selecting this delegates to the existing `exportJourneyMapNotebookLM` and closes the dialog.
- NotebookLM-fit badge per scope: 🟢 < 400K, 🟡 400–500K, 🔴 > 500K.
- Output toggles: `Origin blocks + cross-reference anchors` (default on, disabled), `GLOSSARY.md primer` (default on), `Include Mermaid diagram inline in ARCHITECTURE.md` (default off — sources the same generator as US-EXP-1-13).
- Inline warnings panel above the buttons, visible **before** download: cycles, cross-arch skips, depth-cap hits.
- "Download .zip" disabled in 🔴 state; dialog shows the `split_plan` from US-EXP-1-02 instead.
- Existing two export options on the tile remain unchanged.
- No new menu in `JourneyMatrixTabulator.tsx`.

---

### US-EXP-1-10 — Progress + error handling

**Story:** As a user exporting a large linked bundle, I want visible progress and a graceful failure message so I'm not staring at a frozen button.

**Acceptance:**
- Progress states: `walking graph` → `building markdown` → `zipping` → `downloading`.
- Reuses the existing `ArchExportProgress` interface from `exportArchitectureNotebookLM.ts`.
- Backend warnings (cycles, cross-arch skips, depth cap hits) are surfaced as a post-export toast and written into `_manifest.json.warnings`.
- Cancellation supported via the existing `shouldCancel` pattern.

---

### US-EXP-1-11 — `export_linked_bundle` MCP tool (follow-up)

**Story:** As an AI agent producing a KB for a downstream NotebookLM workflow, I want an MCP tool that returns the bundle so I can pipeline export without a human in the loop.

**Acceptance:**
- Input: `root_map_id` (required), `max_depth?`, `include_agent_manuals?` (default true), `include_children?` (default true).
- Output: `{ url | content_b64, manifest, warnings }`.
- Documented in the MCP server instructions block (`mcp_servers/journey_map.xs` and `ai/mcp_server/journey_map.xs` — both must stay in sync per the repo convention).
- Canonical tool definition lives at `ai/tool/export_linked_bundle.xs`; numbered copy at `tools/{N}_export_linked_bundle.xs`.
- Priority: MED — ship after US-EXP-1-01 through US-EXP-1-10.

---

### US-EXP-1-12 — Round-trip sanity test

**Story:** As the team, I want a test that exports a fixture architecture (parent + 2 sub + 1 exception + 1 ai_agent manual) and asserts the bundle is internally consistent.

**Acceptance:**
- Every anchor referenced in any file exists somewhere in the bundle (no dangling refs).
- Every link in `_manifest.json` is reachable from `ARCHITECTURE.md`.
- Every non-root `README.md` contains a valid origin block referencing an existing parent cell.
- Test lives in `static/src/` alongside the existing `exportMarkdown*.test.ts` patterns.
- Runs in CI; fails on dangling anchors or missing origin blocks.

---

### US-EXP-1-13 — Standalone architecture diagram export (.mmd)

**Story:** As a user, I want a separate menu action that downloads a Mermaid diagram of the map graph so I can paste it into GitHub / Obsidian / Notion / mermaid.live without taking the full bundle.

**Acceptance:**
- New menu item **Export ▸ Architecture diagram (.mmd)** on the per-map tile.
- Opens a small dialog with:
  - **Scope** radio: `From this map (BFS)` (default) vs `Entire architecture`.
  - **Format** radio: `Mermaid (.mmd)` (default) vs `Mermaid in Markdown (.md)` — the `.md` wraps the graph in a ` ```mermaid ` block and prepends a one-line legend.
  - **Edge styling** checkbox: `Color by link type` (default on). Off = monochrome.
- Diagram contents:
  - Node per map: `m{id}["{icon} {title}<br/>{map_level}"]` with `classDef` per map_level.
  - Edge per `journey_link` and per synthesized `agent_manual` link.
  - Edge style by link_type: `sub_journey` solid, `exception` dashed, `anti_journey` dotted, `agent_manual` thick.
  - Cycles drawn (not pruned); cycle edges flagged with comment `%% cycle`.
  - `subgraph` per disconnected tree when scope = `Entire architecture`.
- Reuses the same graph walker (US-EXP-1-01) — no second traversal implementation.
- File name: `{root-slug}-diagram.mmd` or `{architecture-slug}-diagram.mmd`.
- Builder function `buildArchitectureMermaid(graph)` is exported separately so US-EXP-1-09's inline-diagram checkbox can call it without duplication.

---

### US-EXP-1-14 — Per-tile Export submenu reorg

**Story:** As a user, I want the per-tile `…` menu to group export options under an **Export ▸** submenu so the flat list doesn't grow unwieldy as we add the linked-bundle and diagram actions.

**Acceptance:**
- Per-tile `…` menu in `ArchitectureDetail.tsx` gains a single **Export ▸** entry that opens a submenu.
- Submenu groups (with headers):
  - **This map** — `📦 Markdown bundle (.zip)` (existing `onExportMarkdownBundle`), `📓 NotebookLM (.md)` (existing `onExportNotebookLM`).
  - **This map + linked** — `🔗 Linked bundle…` → opens US-EXP-1-09 dialog.
  - **Diagram** — `🗺️ Architecture diagram (.mmd)` → opens US-EXP-1-13 dialog.
- Existing handlers (`onExportMarkdownBundle`, `onExportNotebookLM`) keep their current signatures — only the menu wiring changes.
- Keyboard navigable (arrow keys to traverse, Enter to activate); outside-click closes both menu and submenu.
- No change to the `MapTile` component props beyond two new callbacks (`onExportLinkedBundle`, `onExportDiagram`).

---

## Sequencing

1. **US-EXP-1-01 + 1-02** — backend graph walker + word budget (unblocks everything).
2. **US-EXP-1-03 + 1-08** — anchor scheme + glossary (locks the contract).
3. **US-EXP-1-04 + 1-05 + 1-06** — origin / outbound / callouts (the LLM-comprehension core).
4. **US-EXP-1-07** — architecture entrypoint (map index).
5. **US-EXP-1-14** — menu reorg first (lands empty submenu items wired to TODO handlers).
6. **US-EXP-1-09 + 1-10** — linked-bundle dialog + progress.
7. **US-EXP-1-13** — diagram export (independent track; can ship in parallel with 1-09).
8. **US-EXP-1-12** — test alongside, not after.
9. **US-EXP-1-11** — MCP tool, follow-up.

---

## Relationship to Existing Epics

- **Skill MD Export (SKE)** — different consumer (Augment / Chatbase skill files, single map). EXP-1 is the multi-map NotebookLM-shaped sibling. They share no code path beyond the per-map MD builder.
- **Link Map MCP (LM-1)** — produces the `journey_link` records this exporter consumes. Already shipped.
- **Intelligence Layer / Journey Architecture phase epics** — define `parent_map_id` and `map_level`. Already shipped.

No schema changes required. No automation-snapshot changes required.
