# Account AI Context (AIC) + AI Chat Settings (ACS) — Stories & Status

## Overview
Two epics covering (1) giving the AI awareness of who the account is and (2) letting users control how the AI behaves per map. Both epics are fully implemented in backend and frontend. One gap remains: standalone maps created from the Dashboard were not receiving `account_id`, so the AI context injection was silently skipped for those maps.

---

## Epic 1 — Account-Level AI Context (AIC)

**Goal:** Inject a plain-language company description into every AI conversation so the assistant understands the domain, vocabulary, and priorities of the account without the user having to re-explain it every session.

| Story | Description | Status |
|-------|-------------|--------|
| US-AIC-01 | Add `ai_context` text field to the `account` table | ✅ Done |
| US-AIC-02 | `GET /account/me` returns `ai_context` | ✅ Done |
| US-AIC-03 | `PATCH /account/me` accepts and persists `ai_context` | ✅ Done |
| US-AIC-04 | Orchestrator (`ai_message` POST) fetches account via `journey_map.account_id` and injects `## Company Context` block into dynamic context | ✅ Done |
| US-AIC-05 | Agent system prompt includes `## About Emgram` product context section | ✅ Done |
| US-AIC-06 | `/account` route registered in `main.tsx` pointing to `<AccountSettings />` | ✅ Done |
| US-AIC-07 | `AccountSettings.tsx` — form with AI Context textarea, loads via `getAccountMe`, saves via `updateAccountMe`, accessible from user menu in `ArchitectureDashboard` | ✅ Done |
| US-AIC-08 | `Dashboard.tsx` passes `account_id` from the authenticated user when creating standalone maps so the AI context injection fires | ✅ Fixed (was the only open gap) |

---

## Epic 2 — AI Chat Settings (ACS)

**Goal:** Expose per-map AI behaviour controls (depth, insight quality, focus, reasoning visibility, etc.) to the user instead of having them hardcoded in the agent definition.

Implemented as `smart_ai_settings` — the field set evolved from the original spec to better match the product's actual vocabulary.

| Story | Description | Status |
|-------|-------------|--------|
| US-ACS-01 | Add `smart_ai_settings` JSON column to `journey_map` table with defaults for `interview_depth`, `insight_standard`, `lens_priority`, `emotional_mapping`, `business_impact_framing`, `auto_confirm_writes`, `show_reasoning` | ✅ Done |
| US-ACS-02 | `smart_ai_settings` included in the load bundle response (`GET /journey_map/load/:id`) | ✅ Done |
| US-ACS-03 | `PATCH /journey_map/smart_ai_settings/:journeyMapId` persists settings | ✅ Done |
| US-ACS-04 | Orchestrator reads `smart_ai_settings` from `journey_map` and injects `## AI Behaviour Settings` block into dynamic context | ✅ Done |
| US-ACS-05 | Gear icon in chat header opens `SmartAiSettingsPanel` inside `App.tsx` | ✅ Done |
| US-ACS-06 | Panel loads initial values from the hydrated bundle on mount (`smartAiSettings` state) | ✅ Done |
| US-ACS-07 | Panel saves on every field change via `saveSmartAiSettings` → `PATCH` endpoint | ✅ Done |
| US-ACS-08 | `show_reasoning` setting passed through to `ActivityPanel` to control reasoning visibility | ✅ Done |

---

## Gap Fixed (US-AIC-08)

**Problem:** `Dashboard.tsx` called `createDraftJourneyMap({ title, status })` without `account_id`. Standalone maps (not under a Journey Architecture) were created with `account_id: null`, so the orchestrator's account context lookup returned nothing and the `## Company Context` block was never injected.

**Fix:** `Dashboard.tsx` now reads `user.account_id` from `useAuth()` and passes it when creating a draft map. `XanoUser` already had `account_id` on it — no extra API call required.
