# Chat UX Feedback Epic

## Problem
When a user sends a message to the AI chatbot, two UX issues create a poor experience:
1. The user's own message doesn't appear in the chat until the AI fully responds (10-30s later)
2. There is no visual indicator that the AI is working — the chat area is completely silent during the wait

## Goal
Make the chat feel instant and alive by (a) showing the user's message the moment they send it, and (b) showing an animated thinking indicator while the AI is processing.

---

## Stories

### US-CUX-01 — Optimistic user message display
**File:** `webapp/protype-2/src/App.tsx` — `handleSendMessage`

**Story:** As a user, I want to see my message appear in the chat immediately after I send it so I know it was received, even before the AI responds.

**Root cause:** `setMessages()` is only called after `await sendAiMessage()` resolves. The user's message has no independent state entry — it only appears as part of the full conversation history returned by the server.

**Fix:**
- Immediately before `await sendAiMessage(...)`, push an optimistic message to state:
  ```ts
  setMessages(prev => [...prev, {
    id: `optimistic-${Date.now()}`,
    role: 'expert',
    content: messageText,
    timestamp: new Date(),
  }]);
  ```
- The final `setMessages(taggedMessages)` call (which already happens on success) replaces the full history — the optimistic entry is naturally replaced.
- On error: the `catch` block already restores `inputText`. The optimistic entry will remain visible (it is part of messages state) — this is acceptable, the user can retry.

**AC:**
- User's message appears in the chat list the moment they press Send
- No duplicate message shown after the AI responds
- Error path does not leave a broken state

---

### US-CUX-02 — Animated thinking indicator
**File:** `webapp/protype-2/src/App.tsx` — message list render

**Story:** As a user, I want to see an animated "AI is thinking" bubble below my message while the AI is processing so I know the system is working and roughly how long to wait.

**Fix:**
- After the `messages.map(...)` block and before `lastUpdateSummaries`, conditionally render a thinking bubble when `isSendingMessage === true`:
  ```tsx
  {isSendingMessage && (
    <div className="flex items-start gap-2">
      <div className="w-6 h-6 rounded-full bg-zinc-900 text-white flex items-center justify-center text-[8px] font-bold shrink-0">AI</div>
      <div className="p-3 rounded-xl bg-zinc-100 flex gap-1 items-center">
        <span className="...animate-bounce [animation-delay:0ms]" />
        <span className="...animate-bounce [animation-delay:150ms]" />
        <span className="...animate-bounce [animation-delay:300ms]" />
      </div>
    </div>
  )}
  ```
- The existing `useEffect` that calls `scrollToBottom()` whenever `messages` changes already handles scrolling — the thinking bubble appears after the optimistic user message and scrolls into view automatically.
- When `isSendingMessage` flips to false, the bubble disappears and the AI message replaces it.

**AC:**
- Thinking bubble appears immediately after the user's message
- Three dots animate with staggered bounce timing
- Bubble disappears as soon as the AI response arrives
- Scroll position follows the bubble into view

---

## Out of scope (future epic)
- Real-time token streaming (word-by-word display) — tracked in `product/stories/chat-stream.md`
- Estimated wait time display
- Cancel in-flight request button
