# Epic: Account-Level AI Context (AIC)

**Goal:** Give every Emgram account a persistent "company context" that the AI agent reads before
every conversation — so it understands the industry, terminology, actor types, and workflow norms
of the organisation without the user having to re-explain them each session.

**Why this layer:** The agent system prompt is workspace-global (applies to all Emgram accounts).
Journey settings are map-level. There is no per-account context today. This epic adds that missing
tier so the AI speaks in the customer's language from the very first message.

**Scope:** Schema → backend API → agent orchestrator injection → frontend Account Settings UI.

**Implementation order:** US-AIC-01 → 02 → 03 → 04 → 05 → 06 → 07

---

## US-AIC-01 — Add `ai_context` field to the account table

**As a** platform architect,
**I want** a dedicated `ai_context` text field on the `account` table,
**so that** each company can store freeform AI-readable context separate from the generic `description` field.

**Acceptance Criteria:**
- New nullable `text` field `ai_context` added to `tables/2_account.xs`
- Field is trimmed on write
- Existing `description` field is unchanged (it remains a general company bio)
- No migration needed — field defaults to null for all existing accounts

**Layer:** Backend — `tables/2_account.xs`

---

## US-AIC-02 — `GET /account/me` endpoint

**As a** frontend consumer,
**I want** an authenticated endpoint that returns the current user's account record,
**so that** the UI can display and pre-fill account settings without knowing the account ID in advance.

**Acceptance Criteria:**
- `GET /account/me` endpoint in `Members & Accounts` API group
- Auth required (`auth = "user"`)
- Resolves `account_id` from `$auth` → fetches account record
- Returns: `id`, `name`, `description`, `location`, `ai_context`
- Returns 404 if user has no account linked

**Layer:** Backend — new file `apis/members_accounts/account_me_GET.xs`

---

## US-AIC-03 — `PATCH /account/me/ai_context` endpoint

**As an** account admin,
**I want** to update my account's AI context via a PATCH endpoint,
**so that** changes from the UI are persisted to the backend.

**Acceptance Criteria:**
- `PATCH /account/me/ai_context` in `Members & Accounts` API group
- Auth required; only `admin` role users can write
- Input: `ai_context` (text, nullable), `name` (text, optional), `description` (text, optional)
- Uses `db.edit account` with `field_name = "id"`, `field_value = $user.account_id`
- Returns updated account record
- Rejects non-admin users with `accessdenied` error

**Layer:** Backend — new file `apis/members_accounts/account_me_PATCH.xs`

---

## US-AIC-04 — Inject account context into the `ai_message` orchestrator

**As the** AI agent,
**I want** to receive the account's `ai_context` in my dynamic context block on every turn,
**so that** I understand who the customer is without them needing to explain it in chat.

**Acceptance Criteria:**
- In `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`, after the `$journey_map`
  fetch, add: `db.get account { field_name = "id", field_value = $journey_map.account_id }`
- If `account.ai_context` is not null/empty, append a `## Company Context` block to `$dynamic_context`:
  ```
  ## Company Context
  {account.name}
  {account.ai_context}
  ```
- If `ai_context` is null, the block is omitted — no filler text injected
- Existing `$dynamic_context` structure is unchanged otherwise

**Layer:** Backend — `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`

---

## US-AIC-05 — Add Emgram product context to agent system prompt

**As the** AI agent,
**I want** to understand what Emgram is and who its users are,
**so that** I can handle Emgram-specific journeys (e.g. "map how our users onboard to Emgram")
without the user having to explain the product.

**Acceptance Criteria:**
- A `## About Emgram (platform context)` section added near top of `agents/2_journey_map_assistant.xs`
- Covers: what Emgram is, who uses it (PMs, UX Researchers, BAs), what a stage/lens/cell is,
  typical use cases, and the fact that the AI chat is the primary build interface
- ≤ 120 words — concise, not a sales pitch
- Placed before any behavioural rules so LLM reads it first

**Layer:** Backend — `agents/2_journey_map_assistant.xs`

---

## US-AIC-06 — Account Settings page (UI route)

**As an** account admin,
**I want** an Account Settings page accessible from the user menu,
**so that** I have a dedicated place to manage company-level configuration.

**Acceptance Criteria:**
- New route `/account` in the React app renders an `AccountSettings` page component
- Accessible from the user avatar dropdown in `Dashboard.tsx` and `ArchitectureDashboard.tsx`
  via an "Account Settings" menu item (only visible to `admin` role users)
- Page layout: header with back navigation, two-column form on desktop, single column on mobile
- Loads account data on mount via `GET /account/me`
- Shows loading skeleton while fetching; shows error banner if fetch fails

**Layer:** Frontend — `webapp/protype-2/src/AccountSettings.tsx` (new component), `App.tsx` routing

---

## US-AIC-07 — Account Settings form with AI Context field

**As an** account admin,
**I want** to fill in a plain-language description of my company for the AI,
**so that** every journey map session starts with the AI already understanding our business.

**Acceptance Criteria:**
- Form fields: Company Name (text), Company Description (textarea), Location (text),
  AI Context (large textarea with helper copy)
- AI Context field label: **"What should the AI know about your company?"**
- AI Context placeholder:
  `e.g. We're a B2B logistics platform. Our primary users are ops managers and fleet coordinators.
  Internal teams are called Ops, Growth, and Platform. Our customers are mid-market shippers.`
- Auto-save on blur (same pattern as journey settings panel) OR explicit Save button with spinner
- Success toast: "Company context saved — the AI will use this from your next conversation"
- Non-admin users see the fields in read-only mode with a note: "Only admins can edit account settings"
- Calls `PATCH /account/me/ai_context` on save

**Layer:** Frontend — `webapp/protype-2/src/AccountSettings.tsx`

---

## Story Map

```
Schema        → US-AIC-01 (add ai_context field)
Backend API   → US-AIC-02 (GET /account/me)
              → US-AIC-03 (PATCH /account/me/ai_context)
Agent         → US-AIC-04 (inject into orchestrator)
              → US-AIC-05 (platform context in system prompt)
Frontend      → US-AIC-06 (settings page + route)
              → US-AIC-07 (form + AI context field)
```
