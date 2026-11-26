# US-REPEAT-2-02 — Archive a plan and bring it back

**Epic:** REPEAT-2 · **Size:** S · **Status:** ✅ Built (2026-11-26)
**Depends on:** P3A-1 (endpoint 527, live)

## Description

The server can archive and restore a plan. The screen has no button for either, and no way to see an archived plan. This story adds them.

## Story

**As a** planner, **I want** to archive a plan I no longer need and restore it if I was wrong, **so that** my plan list stays short without losing anything.

## Acceptance (Gherkin)

```gherkin
Scenario: archive
  Given I am on a plan
  When I press Archive plan in Workspace Settings and confirm
  Then the plan leaves the plan list
  And another plan opens

Scenario: see and restore
  When I tick "Show archived" in the plan list
  Then archived plans are listed and marked "archived"
  When I open one and press Restore plan
  Then it is back in the normal list

Scenario: nothing is lost
  Then an archived plan keeps every person, day, job and slot
```

## Counter-measures

- Archive is a confirm, with a sentence saying nothing is deleted and it can be restored.
- Restore is the one write an archived plan accepts (already true on the server).

## Tests

- T-REPEAT2-02-1 archive hides, restore returns (HTTP)
- T-REPEAT2-02-2 the list with and without archived plans (HTTP)
- UT: the list filter and labels
