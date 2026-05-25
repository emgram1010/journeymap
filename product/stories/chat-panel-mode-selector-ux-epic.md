# Chat Panel Mode Selector UX Refactor Epic

**Epic goal:** Replace the overflowing 4-button mode toggle + horizontal pill row in the chat panel header with a single compact badge → popover pattern. Eliminate pill overflow, add a clear deselect path, and give users a persistent active-persona indicator so they always know who they're talking to.

---

## Context & Motivation

The Specialist & Consortium Mode epic (SCM) shipped mode switching and actor pills, but the current implementation has four UX problems discovered in production:

1. **Pill overflow** — 5+ actor pills can't fit in the ~320px chat panel. They wrap to a second row or clip, hiding options without any affordance.
2. **No back-navigation** — once in Specialist or Consortium, there's no obvious single-tap way to exit and return to normal Chat.
3. **Header bloat** — 4 mode buttons + a pill row consumes ~70px of header before the conversation even starts, pushing the message thread down.
4. **Lost context** — after scrolling into the conversation, the user forgets which actor persona is active. The subtitle text is the only indicator and it's easy to miss.

**Research basis:** PatternFly `ChatbotHeaderSelectorDropdown`, librefang model-switcher PR, and cr0x.net filter-bar overflow analysis all converge on the same pattern for constrained-width AI chat panels: a single clickable badge that reflects current state, opening a popover with full selection UI. This is also the pattern ChatGPT uses for model/mode switching.

---

## Dependencies

- `webapp/protype-2/src/App.tsx` — primary change surface; replaces mode toggle + pill row
- `specialist-consortium-mode-epic.md` — must be complete (SCM state vars already in place)

---

## Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | UI pattern | Badge → popover | Eliminates overflow, one line of header space, familiar from ChatGPT/PatternFly |
| 2 | Badge label | Dynamic: reflects active mode + actor | Persistent indicator; user always knows context |
| 3 | Popover content | Mode radio (4 options) + actor list below | Single surface for all switching — no separate pill row needed |
| 4 | Specialist actor list | Radio (single-select) | One actor at a time |
| 5 | Consortium actor list | Checkboxes (multi-select) | Multiple actors simultaneously |
| 6 | Exit/clear | "Clear" link in popover footer + clicking active mode radio deselects | Explicit and discoverable |
| 7 | Popover dismiss | Click outside or press Escape | Standard popover behavior |
| 8 | Remove pill row | Delete separate pill row from header | Replaced entirely by popover |

---

## Priority Stack

```
🔴 HIGH   US-MSR-01  Remove pill row; replace 4-button toggle with mode badge
🔴 HIGH   US-MSR-02  Build mode+actor popover (mode radio + actor list)
🔴 HIGH   US-MSR-03  Specialist single-select actor list in popover
🔴 HIGH   US-MSR-04  Consortium multi-select actor list (checkboxes) in popover
🟡 MEDIUM US-MSR-05  Persistent active-persona subtitle in chat header
🟡 MEDIUM US-MSR-06  Clear/exit affordance — one-tap back to Chat
```

---

## User Stories

### US-MSR-01 — Remove pill row; replace 4-button toggle with mode badge
**Priority:** 🔴 HIGH
**File:** `webapp/protype-2/src/App.tsx`

**Story:** As a user, I want the chat header to show a single compact mode badge instead of four buttons + a pill row, so the conversation takes up more vertical space.

**Changes:**
- Delete the 4-button toggle (`Interview | Chat | 🎭 Specialist | 🏛️ Consortium`) from the header
- Delete the actor pill row below it
- Replace with one badge button: `[🎭 The Lawyer ▾]` / `[🏛️ Panel (3) ▾]` / `[Chat ▾]` / `[Interview ▾]`
- Badge sits inline next to the session title, matching the existing `AI Interviewer ▾` button style

**Acceptance criteria:**
- Header height returns to single line
- Badge label updates dynamically based on `isChatMode`, `chatSubMode`, `activeSpecialistKey`, `activeConsortiumKeys`
- No pill row rendered anywhere in the header

---

### US-MSR-02 — Mode + actor popover
**Priority:** 🔴 HIGH
**File:** `webapp/protype-2/src/App.tsx`

**Story:** As a user, clicking the mode badge opens a popover where I can switch modes and select actors in one place.

**Popover layout:**
```
┌──────────────────────────────┐
│  Switch Mode                  │
│  ○ Interview                  │
│  ○ Chat                       │
│  ○ 🎭 Specialist              │
│  ○ 🏛️ Consortium             │
│  ─────────────────────────── │
│  Speaking as:   (Specialist)  │
│  • The Lawyer     ← radio     │
│  • The Operator               │
│  ─────────────────────────── │
│  [Clear]            [Done]    │
└──────────────────────────────┘
```

**Changes:**
- `isModePopoverOpen` state (bool)
- Popover positioned below the badge, `z-50`, closes on outside click or Escape
- Actor list section renders only when `chatSubMode` is `specialist` or `consortium`
- Actor list sourced from `lenses.filter(l => l.actorType)`

**Acceptance criteria:**
- Popover opens on badge click, closes on outside click / Escape / Done
- Mode change takes effect immediately (optimistic)
- Actor list visible only for Specialist/Consortium modes

---

### US-MSR-03 — Specialist single-select in popover
**Priority:** 🔴 HIGH
**File:** `webapp/protype-2/src/App.tsx`

**Story:** When Specialist mode is selected in the popover, I see a radio list of actors. Selecting one sets `activeSpecialistKey`.

**Changes:**
- Render actor list as `<radio>` inputs when `chatSubMode === 'specialist'`
- Active actor shows filled radio + label in violet
- Selecting a different actor updates `activeSpecialistKey` immediately
- Badge label updates to `🎭 {actorLabel} ▾`

**Acceptance criteria:**
- Only one actor selectable at a time
- Badge reflects the selected actor name
- Deselecting (clicking active radio again) clears to null → badge shows `🎭 Specialist ▾`

---

### US-MSR-04 — Consortium multi-select in popover
**Priority:** 🔴 HIGH
**File:** `webapp/protype-2/src/App.tsx`

**Story:** When Consortium mode is selected, I see a checkbox list. I can select multiple actors; badge shows count.

**Changes:**
- Render actor list as checkboxes when `chatSubMode === 'consortium'`
- Checked actors shown with indigo fill
- Badge label: `🏛️ Panel (N) ▾` where N = `activeConsortiumKeys.length` (or `🏛️ Consortium ▾` if none selected)

**Acceptance criteria:**
- Multiple actors selectable simultaneously
- Badge count updates live as checkboxes toggled
- Unchecking all shows `🏛️ Consortium ▾` — falls back to generic chat behavior (no keys sent)

---

### US-MSR-05 — Persistent active-persona subtitle
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** The chat header subtitle always reflects active mode/persona so the user knows context even mid-conversation.

**Current:** static `"Chat Mode"` / `"Interview Mode"` text
**New:** dynamic label:
- Interview → `Interview Mode`
- Chat → `Chat Mode`
- Specialist + actor selected → `🎭 Speaking as The Lawyer`
- Specialist + no actor → `🎭 Specialist — pick an actor`
- Consortium + actors → `🏛️ Panel · 3 actors`
- Consortium + no actors → `🏛️ Consortium — pick actors`

---

### US-MSR-06 — Clear / exit affordance
**Priority:** 🟡 MEDIUM
**File:** `webapp/protype-2/src/App.tsx`

**Story:** I can exit Specialist or Consortium in one tap without hunting for the right button.

**Changes:**
- `[Clear]` button in popover footer: resets `chatSubMode → 'default'`, clears `activeSpecialistKey` and `activeConsortiumKeys`, sets `isChatMode → true`
- Clicking the already-active mode radio in the popover toggles it off (returns to Chat)
- Clicking the badge while in Chat/Interview opens the popover with correct radio pre-selected

**Acceptance criteria:**
- One tap from Specialist/Consortium → Chat (via Clear)
- No orphaned actor keys after clearing

---

## Out of Scope

- Persisting selected mode/actor to the conversation DB record
- Animated transitions on the popover
- Mobile-specific bottom sheet variant
- Search within the actor list (only needed if actors exceed ~10)
