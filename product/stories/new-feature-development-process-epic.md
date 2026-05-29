# New Feature Development Process — SOP Epic

**Date:** 2026-05-28
**Author:** Engineering Team
**Status:** Active
**Journey Map ID:** 135 (Emgram Platform workspace, id: 17)

---

## Overview

This epic defines the standard operating procedure (SOP) for shipping any new feature on the Emgram platform.
It covers all 9 stages from initial stakeholder agreement through production deploy and summary delivery.

**Platform layers in scope:** Xano DB → API → XanoScript → AI Agents → MCP Server → Frontend → n8n → Xano CLI Deploy

---

## Goal

Ship features safely, consistently, and without regressions — with full traceability from idea to production.

---

## Stages

| # | Stage | Exit Condition |
|---|---|---|
| 1 | User Agreement | Feature approved by stakeholder before any work begins |
| 2 | Create Story File | `product/stories/[feature-slug]-epic.md` exists and is committed |
| 3 | Write Associated Stories | All user stories written with ≥3 acceptance criteria each |
| 4 | Platform Change Planning | All affected layers identified; change plan documented |
| 5 | Regression Review | Existing tests pass; downstream callers verified; risk documented |
| 6 | Execute Feature | Feature implemented across all planned layers; end-to-end tested |
| 7 | Commit Changes | Atomic commit with scoped message; pushed to feature branch |
| 8 | Deploy to Production | Xano CLI deploy (no --force); smoke test passed |
| 9 | Summary & Status | Summary delivered; story file marked shipped |

---

## Platform Layer Checklist (Stage 4 Template)

- [ ] Xano DB — tables, fields, relationships changed?
- [ ] Xano API — new or modified endpoints?
- [ ] XanoScript — business logic changes?
- [ ] AI Agent tools or prompts — updated?
- [ ] MCP server tools — new or modified?
- [ ] Frontend / UI — changes needed?
- [ ] n8n automation flows — endpoints or payloads affected?
- [ ] Xano CLI deploy config — any config changes needed?

---

## Deploy Safety Rules

> **NEVER use `--force` or any destructive flag with Xano CLI.**
> No schema drops. No data migrations without a verified backup.
> If a deploy fails: investigate, fix, redeploy cleanly. Never force through.

Allowed: `xano deploy`
Blocked: `xano deploy --force`, `xano schema drop`, or any command with known destructive side effects.

---

## User Stories

<!-- Stories go below. Follow the format:
### US-XX: [Story Title]
**As a** [role], **I want** [feature], **so that** [outcome].

**Acceptance Criteria:**
1. ...
2. ...
3. ...
-->

_Stories to be added per feature using this SOP._

---

## Notes

- This SOP applies to ALL features regardless of size. "Small" features still require all 9 stages.
- Agreement (Stage 1) must be documented before any file is created.
- The engineer is the primary actor across all stages; AI (Augment) assists in execution.
- Commit directly to `main` is prohibited — always use a feature branch.
