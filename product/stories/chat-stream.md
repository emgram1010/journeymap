## Epic 7: Streaming AI Chat Responses

### Context

The AI agent endpoint (`POST /journey_map/{id}/ai_message`) currently returns the full response in one shot. The user waits with no feedback until the entire agent run completes — LLM reasoning, tool calls, cell updates, and reply assembly all happen before any text appears. This epic adds streaming so the assistant reply renders token-by-token in the sidebar, matching the experience users expect from ChatGPT / Claude.

### Dependencies

- Xano streaming support (available since R1.60 — July 2024): response type `streaming`, `streaming_api_response` function, and `Streaming External API Request` block.
- Existing stories: US-AI-06 (orchestrator endpoint), US-AI-08 (frontend sidebar wired to `/ai_message`).

### Explicit non-goals for this phase

- WebSocket-based bidirectional streaming (SSE / streaming fetch is sufficient).
- Client-side cancel / abort mid-stream (can be added later).
- Streaming tool-call progress or intermediate thinking to the frontend.

---

### US-STREAM-01 — Enable streaming on the Xano AI message endpoint

**Story:** As a backend operator, I want the `/journey_map/{id}/ai_message` endpoint to support a streaming response type so that reply tokens can be pushed to the frontend as they are generated.

**Acceptance Criteria:**
- The endpoint's response type is changed from `standard` to `streaming` in the Xano API settings.
- The orchestrator calls the LLM via the **Streaming External API Request** function (instead of the standard External API Request) so that tokens arrive incrementally.
- Each streamed chunk is forwarded to the client using the `streaming_api_response` function inside a For Each loop.
- After all reply tokens are sent, a final chunk is emitted containing the structured metadata (`cell_updates`, `structural_changes`, `progress`, `conversation`, `messages`).
- If the calling client does not support streaming (no `text/event-stream` accept), Xano falls back to delivering the full response at once (built-in Xano behavior).

---

### US-STREAM-02 — Define the streaming event contract

**Story:** As a frontend developer, I need a documented event format for each streamed chunk so that the client knows how to parse tokens vs. metadata.

**Acceptance Criteria:**
- Each text-token chunk is a JSON object: `{ "type": "token", "content": "<partial text>" }`.
- The final metadata chunk is a JSON object: `{ "type": "done", "cell_updates": [...], "structural_changes": {...}, "progress": {...}, "conversation": {...}, "messages": [...] }`.
- An error chunk format is defined: `{ "type": "error", "message": "<error description>" }`.
- The contract is consistent enough that the frontend can switch on `type` to route handling.

---

### US-STREAM-03 — Persist messages and apply cell updates after stream completes

**Story:** As the system, I want message persistence and cell mutations to happen after the full reply has been generated so that partial/failed streams do not leave orphaned records.

**Acceptance Criteria:**
- The user message is persisted **before** the stream starts (so the user sees it immediately).
- The assistant reply is accumulated server-side during streaming and persisted **after** the stream completes.
- Cell updates and structural changes are applied **after** the full reply is assembled (same as today).
- If the stream is interrupted or errors mid-way, no assistant message or cell updates are saved.

---

### US-STREAM-04 — Frontend: consume the streaming response

**Story:** As a user, I want to see the AI reply appear word-by-word in the chat sidebar so that the experience feels responsive and conversational.

**Acceptance Criteria:**
- The frontend uses `fetch` + `ReadableStream` (not `EventSource`, since the request is POST) to call the streaming endpoint.
- As each `token` chunk arrives, the partial reply is appended to a new AI message bubble in real time.
- The message input is disabled and a typing indicator is shown while the stream is in progress.
- When the `done` chunk arrives, `cell_updates` are applied to the matrix, `structural_changes` trigger a grid refresh, progress is updated, and the conversation record is stored in state.
- If an `error` chunk arrives, the error is displayed inline in the chat and the UI returns to an idle state.

---

### US-STREAM-05 — Update `xano.ts` types and client function

**Story:** As a developer, I want the `sendAiMessage` function to support streaming so that the rest of the app can call one function and get progressive updates via a callback.

**Acceptance Criteria:**
- A new function (or overload) `sendAiMessageStream` is added to `xano.ts`.
- It accepts the same inputs as `sendAiMessage` plus an `onToken(text: string)` callback.
- It returns a `Promise<AiMessageResponse>` that resolves with the final metadata when the stream completes.
- The existing non-streaming `sendAiMessage` continues to work as a fallback.
- The `AiMessageResponse` type does not need to change — it matches the `done` chunk payload.

---

### US-STREAM-06 — Graceful degradation when streaming is unavailable

**Story:** As a user on a client or network that doesn't support streaming, I want the chat to still work with the full response delivered at once so that nothing breaks.

**Acceptance Criteria:**
- If the `ReadableStream` API is not available in the browser, the frontend falls back to the existing non-streaming `sendAiMessage` call.
- If the Xano endpoint detects a client that can't accept streaming, it delivers the full JSON response (built-in Xano behavior).
- The AI sidebar behaves identically in both paths — only the perceived latency differs.

---

### US-STREAM-07 — Validation and testing

**Story:** As the team shipping streaming, we want tests confirming the end-to-end flow works for both streaming and non-streaming clients.

**Acceptance Criteria:**
- A Xano workflow test confirms the endpoint streams chunks in the expected format (`token` → `token` → … → `done`).
- A Playwright E2E test confirms the sidebar progressively renders the reply (not all at once).
- A fallback test confirms the app still works when streaming is disabled or unsupported.
- Existing chat E2E tests (`ai-prompt-phase1.spec.ts`, `chat-session-crud.spec.ts`) still pass.

---

### Recommended implementation sequence

```
US-STREAM-02 (contract) → US-STREAM-01 (backend) → US-STREAM-03 (persistence) → US-STREAM-05 (client fn) → US-STREAM-04 (frontend) → US-STREAM-06 (fallback) → US-STREAM-07 (tests)
```

Define the contract first. Then wire the backend. Then build the client function. Then integrate into the UI. Then harden with fallback and tests.

### Architecture reference

```
User sends message
    │
    ▼
Frontend: fetch POST /ai_message (Accept: text/event-stream)
    │
    ▼
Xano orchestrator (response type: streaming)
    │
    ├── Persist user message
    ├── Call LLM via Streaming External API Request
    │     │
    │     ▼
    │   For Each token chunk:
    │     └── streaming_api_response({ type: "token", content: "..." })
    │
    ├── Accumulate full reply
    ├── Apply cell updates + structural changes
    ├── Persist assistant message
    │
    └── streaming_api_response({ type: "done", cell_updates, progress, ... })
    │
    ▼
Frontend: onToken → append to bubble │ onDone → apply matrix updates
```
