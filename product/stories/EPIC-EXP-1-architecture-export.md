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
  "architecture_id": 7,
  "visited_map_ids": [126, 127, 130, …],
  "links": [ { "source_map":126, "target_map":127, "link_type":"sub_journey|exception|anti_journey|parent_child|agent_manual", "label":"…", "source_lens": 42, "source_lens_label": "Handoff" } ],
  "warnings": [ { "type": "depth_cap", "detail": "…" } ],
  "walk_status": "complete|depth_capped"
}
```

**Acceptance:**
- Walks `journey_link`, `journey_lens.agent_map_id`, and `journey_map.parent_map_id` per the traversal rules.
- Cycle detection: each map visited at most once.
- Depth-capped traversals recorded in `warnings` with unexplored count.
- Synthesises edge records for `parent_child` and `agent_manual` traversals (not real `journey_link` rows) so the consumer sees a uniform graph.
- `agent_manual` edges include `source_lens` (lens id) and `source_lens_label` so US-EXP-1-04 can render the parent-lens reference in the origin block without an extra round-trip.
- Tenant-scoped via existing `owner_user` filter on the root map (same pattern as `get_map`); architecture-scoped on bulk-fetch of maps + links.
- Bulk-fetches all `journey_map` + `journey_link` rows for the architecture once; only `journey_lens` is queried per frontier node (bounded by visited count, not depth × N).
- **Hydration is deferred** to the consumer (see US-EXP-1-01b): the walker returns IDs + edges only; the frontend hydrates per-map bundles in parallel.

---

### US-EXP-1-01b — Frontend graph client + parallel hydration

**Story:** As the exporter, I need a single FE module that calls the walker, hydrates every visited map via `load_bundle`, and exposes one in-memory graph object that downstream builders (1-04 / 1-09 / 1-13 / 1-15) consume.

**Module:** `static/src/linkedGraphClient.ts`

**Public API:**
```ts
export interface LinkedGraph {
  rootMapId: number;
  architectureId: number;
  maps: Map<number, JourneyMapBundle>;  // hydrated via load_bundle
  links: LinkedGraphEdge[];              // includes synthesized parent_child + agent_manual
  warnings: WalkerWarning[];
  walkStatus: 'complete' | 'depth_capped';
  bfsOrder: number[];                    // visited_map_ids in BFS order (for folder numbering)
}

export async function fetchLinkedGraph(
  rootMapId: number,
  opts?: { maxDepth?: number; includeAgentManuals?: boolean; includeChildren?: boolean;
           signal?: AbortSignal; onProgress?: (p: { phase: 'walking'|'hydrating'; done: number; total: number }) => void }
): Promise<LinkedGraph>
```

**Acceptance:**
- Calls `GET /journey_map/{rootMapId}/export/linked_graph` first.
- Fan-out: `Promise.all` over `visited_map_ids[]`, each calling `load_bundle/{id}`. Concurrency cap (default 8) to avoid Xano rate limit.
- Single retry per map on transient (network) failure; final failure pushes a `hydrate_failed` warning, does **not** abort the whole graph.
- `signal` honoured (AbortController) — aborts in-flight `load_bundle` calls.
- `onProgress` fires once after the walk and after each successful hydrate.
- No DOM dependencies — pure module so US-EXP-1-12 can unit-test it.
- Imports the existing fetch wrapper (same pattern as `exportMarkdownBundle.ts`).

---

### US-EXP-1-02 — Frontend word-budget pre-flight

**Story:** As the exporter, given a hydrated `LinkedGraph`, I want per-map and total word counts plus a `split_plan` when the bundle overflows, so the dialog can warn or refuse before zipping.

**Module:** `static/src/linkedGraphBudget.ts` *(frontend — no backend changes)*

**Public API:**
```ts
export function computeWordBudget(graph: LinkedGraph): {
  perMap: Map<number, number>;
  total: number;
  fitBadge: 'green' | 'yellow' | 'red';  // <400K / 400–500K / >500K
  splitPlan?: { rootMapId: number; includedMaps: number[]; wordCount: number }[];
}
```

**Acceptance:**
- Pure function over the hydrated graph — no I/O.
- Reuses `countWords` from `exportMarkdownNotebookLM.ts`.
- `splitPlan` only present when `total > 500_000`; partitions the graph into the fewest BFS sub-trees that each fit.
- US-EXP-1-09 dialog renders the badge + plan; US-EXP-1-15 reuses for per-file fit.

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

### US-EXP-1-09b — Core linked-skill builder

**Story:** As the dialog (1-09) and the MCP tool (1-11), I need a pure builder function that turns a `LinkedGraph` + traversal options into a `.zip` blob, so UI and headless callers share one code path.

**Module:** `static/src/exportLinkedSkillBundle.ts`

**Public API:**
```ts
export interface LinkedSkillOptions {
  traversal: 'all_linked' | 'sub_only' | 'exception_only';
  includeOriginBlocks: boolean;     // default true (forced on in dialog)
  includeGlossary: boolean;          // default true
  includeInlineDiagram: boolean;     // default false
}

export async function buildLinkedSkillBundle(
  graph: LinkedGraph,
  opts: LinkedSkillOptions,
  onProgress?: (phase: 'building'|'zipping', done: number, total: number) => void
): Promise<{ blob: Blob; filename: string; manifest: ManifestV1 }>
```

**Acceptance:**
- Orchestrates US-EXP-1-03 (anchors) → 1-04 (origin blocks) → 1-05 (outbound links) → 1-06 (callouts) → 1-07 (ARCHITECTURE.md) → 1-08 (GLOSSARY.md) → 1-10b (manifest) → JSZip.
- Filters the graph by `opts.traversal` before building (drops edges + unreached maps).
- BFS-orders maps for stable `maps/NN-{slug}/` folder numbering.
- Reuses `buildJourneyMapFiles` from `exportMarkdownBundle.ts` for per-map per-stage content — no duplication.
- Returns the manifest alongside the blob so the dialog can show post-export warnings without re-reading the zip.
- Pure: no DOM, no fetch — testable in US-EXP-1-12.

---

### US-EXP-1-09 — "Skill bundle (linked)" dialog with traversal picker

**Story:** As a user opening the **Export ▸ This map + linked ▸ Skill bundle (.zip)…** action on a map tile, I want a dialog that lets me choose which edge types to traverse (all linked, sub-journeys only, or exceptions only) before downloading.

**Acceptance:**
- Dialog header shows the root map title, `map_level`, and `m{id}`.
- On open, calls `fetchLinkedGraph` (US-EXP-1-01b) once with the broadest scope (`all_linked`); subsequent radio changes re-filter in memory using `computeWordBudget` over the filtered subgraph — no extra network round-trips.
- Traversal radio group with three mutually-exclusive options, each showing live counts `{map count} · {word count} · {fit badge}`:
  - `All linked` (default) — sub_journey + exception + anti_journey + agent_manual edges.
  - `Sub-journeys only` — `link_type = sub_journey` and `agent_map_id` edges.
  - `Exceptions only` — `link_type = exception`.
- "Parent only" is **not** in this dialog — it is reachable from the top-level **This map ▸ Skill (.zip)** menu item, which calls the existing single-map `exportJourneyMapBundle` directly. Picking that path never opens this dialog.
- NotebookLM-fit badge per option: 🟢 < 400K, 🟡 400–500K, 🔴 > 500K.
- Output toggles: `Origin blocks + cross-reference anchors` (default on, disabled), `GLOSSARY.md primer` (default on), `Include Mermaid diagram inline in ARCHITECTURE.md` (default off — sources the same generator as US-EXP-1-13).
- Inline warnings panel above the buttons, visible **before** download: cycles, cross-arch skips, depth-cap hits.
- "Download .zip" disabled in 🔴 state; dialog shows the `split_plan` from US-EXP-1-02 instead.
- On confirm: calls `buildLinkedSkillBundle` (US-EXP-1-09b) — dialog owns UI only, never builder logic.
- Output filename: `{root-slug}-skill-linked.zip`.
- Existing two single-map export options on the tile remain unchanged.
- No new menu in `JourneyMatrixTabulator.tsx`.

---

### US-EXP-1-10b — `_manifest.json` builder

**Story:** As an LLM (or downstream automation) consuming the bundle, I need a single machine-readable manifest at the root so I can index maps, links, anchors, and warnings without parsing every Markdown file.

**Module:** `static/src/exportLinkedManifest.ts`

**Schema (`ManifestV1`):**
```ts
{
  schema_version: 1,
  generated_at: string,            // ISO 8601
  root_map_id: number,
  architecture_id: number,
  traversal: 'all_linked' | 'sub_only' | 'exception_only',
  walk_status: 'complete' | 'depth_capped',
  maps: Array<{
    map_id: number;
    slug: string;                  // m{id}-{title-slug}
    folder: string;                // maps/NN-{slug}
    title: string;
    map_level: 'architecture'|'actor-journey'|'atomic'|null;
    depth_from_root: number;
    word_count: number;
    parent: { link_type: string; source_map: number; source_cell?: string; source_lens?: number } | null;
  }>,
  links: Array<{
    source_map: number; target_map: number;
    link_type: 'sub_journey'|'exception'|'anti_journey'|'agent_manual'|'parent_child';
    label: string | null;
    source_cell?: string;          // CELL anchor
    source_lens?: number;
  }>,
  word_counts: { total: number; per_map: Record<number, number> },
  warnings: Array<{ type: string; detail: string }>
}
```

**Acceptance:**
- Pure builder: `buildLinkedManifest(graph, opts): ManifestV1` — no I/O.
- Emitted at the bundle root as `_manifest.json` (pretty-printed, 2-space indent).
- `parent.source_cell` is the canonical `[CELL:m…/sN×lN]` anchor (from US-EXP-1-03) so manifest entries cross-reference the Markdown anchors.
- Warnings include walker warnings + hydrate failures + any builder-time issues (e.g. cross-arch skips).
- Consumed by US-EXP-1-09 dialog (post-export toast), US-EXP-1-11 (MCP wrapper return value), and US-EXP-1-12 (round-trip test).

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

### US-EXP-1-14 — Per-tile Export submenu (scope-first IA)

**Story:** As a user, I want the per-tile `…` menu to group export options under an **Export ▸** submenu organised by *scope first, format second*, so the choice of "this map vs this map + linked" is the primary decision and format ("skill bundle" vs "NotebookLM") is the secondary one.

**Acceptance:**
- Per-tile `…` menu in `ArchitectureDetail.tsx` gains a single **Export ▸** entry that opens a submenu.
- Submenu groups (with headers), in this order:
  - **This map**
    - `📄 Skill (.zip)` → existing `onExportMarkdownBundle` → `{slug}-skill.zip`
    - `📓 NotebookLM (.md)` → existing `onExportNotebookLM` → `{slug}-notebooklm.md`
  - **This map + linked**
    - `📄 Skill bundle (.zip)…` → opens US-EXP-1-09 dialog → `{slug}-skill-linked.zip`
    - `📓 NotebookLM bundle (.zip)…` → opens US-EXP-1-15 dialog → `{slug}-notebooklm-linked.zip`
  - **Diagram**
    - `🗺️ Architecture diagram (.mmd)` → opens US-EXP-1-13 dialog → `{slug}-diagram.mmd`
- Existing handlers (`onExportMarkdownBundle`, `onExportNotebookLM`) keep their current signatures — only the menu wiring changes; filename naming is updated to match the `{slug}-skill.zip` / `{slug}-notebooklm.md` convention.
- Keyboard navigable (arrow keys to traverse, Enter to activate); outside-click closes both menu and submenu.
- `MapTile` component gains four new callback props: `onExportLinkedBundle`, `onExportLinkedNotebookLM`, `onExportDiagram` (plus the two existing ones, unchanged).

---

### US-EXP-1-15 — Linked NotebookLM bundle (.zip of MD files)

**Story:** As a user wanting to feed *this map + everything linked* into NotebookLM as a multi-source pack, I need a `.zip` of independent `.md` files (one per map) so each map is a separate NotebookLM source — preserving cross-map citations while staying under the 500K-word-per-source limit.

**Acceptance:**
- Triggered from per-tile menu **Export ▸ This map + linked ▸ NotebookLM bundle (.zip)…**.
- Reuses the US-EXP-1-01 graph walker to enumerate reachable maps (sub / exception / anti / agent-manual).
- Reuses the US-EXP-1-02 word-budget calculator; per-map word count and aggregate are surfaced in the dialog.
- Output layout:
  ```
  {root-slug}-notebooklm-linked/
  ├── 00-INDEX.md                  catalogue: which file is which, with anchor table
  ├── 01-{root-slug}.md            single-file NotebookLM build of root map
  ├── 02-{sub-slug}.md             …with Origin block referencing root via [CELL:m{root}/sN×lN]
  └── …
  ```
- Each per-map `.md` is the same shape as today's `exportJourneyMapNotebookLM` output, plus the Origin block from US-EXP-1-04 inlined at the top for non-root maps.
- Same anchor scheme as the skill bundle (US-EXP-1-03) so cross-file citations resolve.
- Dialog mirrors US-EXP-1-09 traversal picker (all linked / sub-only / exception-only).
- Per-file fit badge: 🟢 < 400K words, 🟡 400–500K, 🔴 > 500K (file split required — error, not warn).
- Output filename: `{root-slug}-notebooklm-linked.zip`.
- New builder: `buildLinkedNotebookLMZip(graph)` in a new module `static/src/exportLinkedNotebookLM.ts` (reuses `buildJourneyMapNotebookLM` per map).

---

## Sequencing

1. ✅ **US-EXP-1-14** — menu reorg (shipped; stubs alert "coming soon").
2. ✅ **US-EXP-1-01** — backend graph walker endpoint (shipped to Xano).
3. **US-EXP-1-01b** — FE `linkedGraphClient.ts` (walker + parallel hydrate). *Bridge: unblocks 1-02 / 1-04 / 1-09 / 1-13 / 1-15.*
4. **US-EXP-1-02** — FE `linkedGraphBudget.ts` (pure function over hydrated graph).
5. **US-EXP-1-03 + 1-08** — anchor helpers + glossary (locks the contract).
6. **US-EXP-1-04 + 1-05 + 1-06** — origin block / outbound-links file / inline callouts (LLM-comprehension core).
7. **US-EXP-1-07** — `ARCHITECTURE.md` map-index entrypoint.
8. **US-EXP-1-10b** — `_manifest.json` builder.
9. **US-EXP-1-09b** — core `buildLinkedSkillBundle` orchestrator (pure, headless-friendly).
10. **US-EXP-1-09 + 1-10** — dialog UI + progress / cancellation wiring.
11. **US-EXP-1-15** — linked NotebookLM `.zip` builder + dialog (parallel with 1-09 once 1-04 lands).
12. **US-EXP-1-13** — diagram `.mmd` export (independent; reuses walker only).
13. **US-EXP-1-12** — round-trip sanity test (lands alongside 1-09b, not after).
14. **US-EXP-1-11** — MCP tool wrapper (follow-up; consumes 1-09b).

---

## Relationship to Existing Epics

- **Skill MD Export (SKE)** — different consumer (Augment / Chatbase skill files, single map). EXP-1 is the multi-map NotebookLM-shaped sibling. They share no code path beyond the per-map MD builder.
- **Link Map MCP (LM-1)** — produces the `journey_link` records this exporter consumes. Already shipped.
- **Intelligence Layer / Journey Architecture phase epics** — define `parent_map_id` and `map_level`. Already shipped.

No schema changes required. No automation-snapshot changes required.
