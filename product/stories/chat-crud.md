## Epic 6: AI Agent Chat Session Management

### Context

US-08 established conversation persistence, and US-13 wired the frontend sidebar to persisted chat. This epic adds full lifecycle management so users can create, browse, rename, and delete conversation sessions tied to a journey map.

---

### US-17 — List conversation sessions for a journey map

**Story:** As a product operator, I want to see all conversation sessions tied to my journey map so that I can find and resume past interview or chat threads.

**Acceptance Criteria:**
- A GET endpoint returns all `agent_conversation` records for a given `journey_map_id`, ordered by `last_message_at` descending.
- Each record includes `id`, `title`, `mode`, `last_message_at`, and a `message_count` (total messages in the thread).
- An empty list is returned when no conversations exist (not an error).
- The frontend can render a session picker list from this response.

---

### US-18 — Load a specific conversation session with messages

**Story:** As a user switching between past sessions, I want to load a specific conversation and its full message history so that the AI sidebar shows the correct thread.

**Acceptance Criteria:**
- A GET endpoint accepts a `conversation_id` and returns the conversation record plus all its `agent_message` records ordered by `created_at` ascending.
- The endpoint validates that the conversation belongs to the provided `journey_map_id` (or returns a clear error).
- Message content is returned in the same shape the frontend already consumes from the `load_bundle` and `ai_message` responses.
- If the conversation does not exist, a `404` is returned.

---

### US-19 — Create a new conversation session

**Story:** As a user, I want to explicitly start a new conversation thread so that I can begin a fresh interview or chat session without it being auto-created on first message.

**Acceptance Criteria:**
- A POST endpoint creates a new `agent_conversation` record for the given `journey_map_id`.
- The request accepts an optional `title` (defaults to "New Conversation") and a required `mode` (`interview` or `chat`).
- The response returns the created conversation record.
- The existing auto-create logic in the message endpoints continues to work as a fallback for backward compatibility.

---

### US-20 — Update conversation session metadata

**Story:** As a user, I want to rename a conversation or change its mode so that I can keep my session list organized and meaningful.

**Acceptance Criteria:**
- A PATCH endpoint accepts a `conversation_id` and allows updating `title` and/or `mode`.
- Empty or whitespace-only titles are rejected with a user-friendly error.
- Mode values are validated to `interview` or `chat`.
- The response returns the updated conversation record.
- The endpoint validates the conversation belongs to the specified `journey_map_id`.

---

### US-21 — Delete a conversation session

**Story:** As a user, I want to delete a conversation session I no longer need so that my session list stays clean and relevant.

**Acceptance Criteria:**
- A DELETE endpoint accepts a `conversation_id` and removes the conversation record.
- All `agent_message` records belonging to that conversation are cascade-deleted.
- The endpoint validates the conversation belongs to the specified `journey_map_id` before deleting.
- If the deleted conversation was the only one, subsequent `load_bundle` calls return an empty conversation payload (not an error).
- The response confirms deletion with the deleted conversation's `id`.

---

### US-22 — Delete an individual message from a conversation

**Story:** As a user reviewing a conversation, I want to delete a specific message so that I can remove incorrect or irrelevant entries from the thread.

**Acceptance Criteria:**
- A DELETE endpoint accepts a `message_id` and removes the single `agent_message` record.
- The endpoint validates the message belongs to a conversation owned by the specified `journey_map_id`.
- The parent conversation's `last_message_at` is recalculated to the most recent remaining message (or set to `null` if no messages remain).
- The response confirms deletion with the deleted message's `id`.

---

### US-23a — Frontend session picker: list, load, and create

**Story:** As a user, I want a session picker in the AI sidebar so that I can browse past conversations, switch between them, and start new sessions without leaving the workspace.

**Acceptance Criteria:**
- The AI sidebar shows the current conversation title and mode at the top.
- A dropdown or list panel displays all sessions for the active journey map (from US-17).
- Selecting a session loads its messages into the sidebar (from US-18).
- A "New Session" action creates a fresh conversation (from US-19).
- The session list updates without a full page reload.
- Loading and error states are visible during session switches.

---

### US-23b — Frontend session management: rename and delete

**Story:** As a user, I want to rename and delete conversation sessions from the sidebar so that I can keep my session list organized.

**Acceptance Criteria:**
- An inline rename action updates the conversation title (from US-20).
- A delete action removes a session with a confirmation prompt (from US-21).
- After deleting the active session, the sidebar falls back to the most recent remaining session or shows an empty state.
- Optionally, individual messages can be deleted from the active conversation (from US-22).
- The session list reflects changes immediately without a full page reload.

---

### US-24 — Session picker dropdown affordance (pill/chip style)

**Story:** As a user, I want the session picker trigger in the AI sidebar header to look obviously clickable so that I can discover and use the session list without guessing.

**Acceptance Criteria:**
- The conversation title + chevron is wrapped in a bordered pill/chip with a subtle background (similar to the Interview/Chat toggle).
- On hover the pill shows a distinct background change to reinforce interactivity.
- The chevron rotates when the dropdown is open (existing behavior retained).
- The pill does not visually compete with the Interview/Chat toggle — use a lighter/outlined style.

---

### Recommended implementation sequence

```
US-17 (list) → US-18 (read one) → US-19 (create) → US-23a (frontend: list/load/create) → US-20 (update) → US-21 (delete conversation) → US-22 (delete message) → US-23b (frontend: rename/delete) → US-24 (dropdown affordance)
```

### Dependencies

- US-17 through US-19 must be available before US-23a.
- US-20 through US-22 must be available before US-23b.
- All backend stories depend on the existing `agent_conversation` and `agent_message` tables from US-01.
- No schema changes are required — the current tables support all operations.
