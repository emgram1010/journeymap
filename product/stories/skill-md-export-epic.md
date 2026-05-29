# Epic: Export Journey Map as Skill MD File

**Epic ID:** SKE
**Status:** Planned

Allow users to export one or many journey maps as `.md` skill files that AI copilots (Augment, Chatbase, etc.) can read directly from the filesystem as a zero-latency knowledge base.

---

## US-SKE-01 — Backend: Skill MD export endpoint

**Story:** As a frontend engineer, I need an endpoint that returns a journey map formatted as a Skill MD file so the browser can trigger a file download.

**Endpoint:** `GET /journey_map/{journey_map_id}/export/skill_md`
**Auth:** `user` (owner-scoped)
**Response:** `text/markdown` + `Content-Disposition: attachment; filename={slugified-title}.md`

**Output format:**
```
# Skill: {map.title}

## Metadata
- **Intent:** {map.intent}
- **Primary Actor:** {map.primary_actor}
- **Scope:** {map.journey_scope}
- **Start:** {map.start_point}
- **End:** {map.end_point}
- **Duration:** {map.duration}
- **Success Metrics:** {map.success_metrics}
- **Key Stakeholders:** {map.key_stakeholders}
- **Dependencies:** {map.dependencies}

## When to use
{map.pain_points_summary}

---

## Stages

### Stage N — {stage.label}
**Goal:** {stage.stage_goal}
**Primary Actor:** {resolved lens label for stage.primary_actor_lens}

#### {lens.label}
{cell.content}

---
```

**Acceptance Criteria:**
- [ ] Fetches map, stages (by display_order), lenses (by display_order), and cells
- [ ] Resolves primary_actor_lens key to lens label for each stage
- [ ] Omits metadata fields that are null or empty
- [ ] Omits cells where content is null and status is open
- [ ] Slug: title lowercased, spaces to hyphens, special chars stripped
- [ ] Returns 404 if map not found or not owned by authenticated user
- [ ] Returns 401 for unauthenticated requests

---

## US-SKE-02 — Frontend: Export single map from context menu

**Story:** As a user, I want to export any map as a Skill MD file from its tile context menu.

**Affects:** `Dashboard.tsx` (MapTile) and `ArchitectureDetail.tsx` (MapTile)

**Acceptance Criteria:**
- [ ] MoreHorizontal menu gains "Export as Skill MD" item between Duplicate and Archive
- [ ] On click: calls GET /journey_map/{id}/export/skill_md with auth token
- [ ] Response downloaded as a file via URL.createObjectURL — no new tab opened
- [ ] Filename comes from Content-Disposition header
- [ ] Menu item shows spinner and is disabled while request is in-flight
- [ ] On error: inline error text in menu — "Export failed — try again"
- [ ] Works identically in both Dashboard.tsx and ArchitectureDetail.tsx

---

## US-SKE-03 — Frontend: Export multiple maps from Architecture view

**Story:** As a user, I want to select multiple maps inside an architecture and export them all as Skill MD files.

**Affects:** `ArchitectureDetail.tsx`

**Acceptance Criteria:**
- [ ] "Select" toggle button added to architecture header next to + New Map
- [ ] When active, each MapTile shows a checkbox — clicking toggles it instead of opening the map
- [ ] Sticky bottom bar appears when 1 or more maps are selected: "{N} map(s) selected  [Export as Skill MD]  [Cancel]"
- [ ] Export calls GET /journey_map/{id}/export/skill_md for each selected map sequentially with 150ms between calls
- [ ] Each file downloads as its request resolves
- [ ] Bar shows progress: "Exporting 2 of 3..." then "3 files exported" for 2s then resets
- [ ] "Cancel" deselects all and dismisses bar
- [ ] Select mode hidden when viewMode === "graph"
- [ ] Archived maps excluded from export
