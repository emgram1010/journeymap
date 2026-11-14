# EPIC-SEC-3 — Lock the AI tool door

**Status:** 🟡 **The door is shut and proven (stories 01–03 ✅, 2026-11-14, Fable 5.2).** Stories 04 (tenancy inside tools → COP-1), 05 (refusal logging) and part of 06 (nightly probe) are open. Founder said "yes on the sign-in" 2026-11-14.
**Model:** **Opus 5.5** (or Fable 5.2). A guard on a public address. Review pass after.
**Depends on:** USR-2 (live). **Goes before COP-1** — COP-1's stories assume this door is shut.
**Risk:** high both ways: left open, anyone reads any customer's maps; shut wrongly, every
outside assistant (and possibly the founder's own) is locked out.

---

## 1. Goal

**Pain:** the address that outside AI assistants use to reach Emgram's map tools answers with
**no sign-in**. Anyone who has it can list and run all 21 tools — read, create, edit and publish
any account's maps by guessing map numbers.

**Fix:** no valid token, no tools. A signed-in caller must also be switched on and hold the
Intelligent Layer, exactly like a person on the screen.

**Win:** a stranger gets nothing. The founder's own assistant keeps working once it carries a token.

---

## 2. What was found (live, real HTTP, no token, 2026-11-14)

| Check | Result |
|---|---|
| `tools/list` on `…/x2/mcp/ju0Zh1JM/mcp/stream` | 🔴 all 21 tools listed |
| `tools/call get_map {journey_map_id: 226}` | 🔴 the whole map returned (the founder's own test map; no other map was read) |
| Cause | The server's "Auth Gate" trigger (id 2, server id 8) has its check commented out: `// AUTH GATE TEMPORARILY DISABLED — testing public access`. Live copy last changed 2026-06-18 |
| Why it matters more than one switch | The tools never look at who is calling and never check the account. The gate was the **only** lock |
| Side effect already seen | Maps made through the tools have owner 0 and account 0 (architecture 46, maps 226–234) |

**Not the in-app chat.** The chat inside Emgram calls the agent from a signed-in endpoint
(api 52, owner check on the map). It does not use this address.

---

## 3. Design

```
Outside assistant ──▶ tool address
                        │
                        ▼
              Is there a valid token?            no → refused, nothing listed, nothing run
                        │ yes
                        ▼
              Is this person switched on,        no → refused with the same friendly message
              and granted the Intelligent Layer?      a person gets on the screen
                        │ yes
                        ▼
                    tools work
```

- **One rule, already written.** The second check is `usr/assert_module_access` — the same function
  the screen's gate calls. No second copy.
- **Fails closed.** If the caller cannot be identified for any reason, the answer is no.
- **What this does not do:** it does not stop a signed-in, granted user from asking for another
  account's map by number. That is tenancy inside each tool — story 04 here hands it to COP-1.

---

## 4. Stories

### US-SEC-3-01 — No sign-in, no tools
**Status:** ✅ Built and proven live (Fable 5.2, 2026-11-14).

**As** the founder, **I want** the tool address to refuse anyone without a valid token,
**so that** a stranger cannot read or change a customer's maps.

```gherkin
Scenario: Listing tools without a token is refused
  When the address is asked for its tools with no token
  Then it is refused and no tool is listed

Scenario: Running a tool without a token is refused
  When get_map is called with no token
  Then it is refused and no map content is returned

Scenario: A made-up token is refused
  When the address is called with a token that is not valid
  Then it is refused
```

**Build notes.** Fetch the **live** trigger and edit that — it has inputs the local file lacks
(`prompts`, `resources`, `json? auth`). Not known in advance whether the caller arrives as `$auth`
or `$input.auth`: prove it with a token call right after the push. Fail closed while finding out.
Then bring both local copies (`ai/mcp_server/trigger/auth_gate.xs`,
`mcp_servers/triggers/2_auth_gate.xs`) in line with live.

### US-SEC-3-02 — A signed-in caller still works
**Status:** ✅ Built and proven live with a test user (Fable 5.2, 2026-11-14). ⏳ The founder's own assistant still needs its token — steps in §9.

**As** the founder, **I want** my own assistant to keep working once it carries a token,
**so that** closing the door does not close it on me.

```gherkin
Scenario: A valid token gets the tools
  Given a valid token for a person who is switched on and has the Intelligent Layer
  When the address is called with it
  Then the tools are listed and a read works

Scenario: Reconnecting is written down
  Then the epic lists the exact steps to add a token to an outside assistant's address
  And the token itself is never pasted into a chat, a map or a log
```

**Build notes.** Tokens come from the existing `automation_api_token/generate` (api 197, 1-year,
same type as a session). The founder creates their own token; nobody else handles it.

### US-SEC-3-03 — Same rules as a person: switched on, and granted
**Status:** ✅ Built (Fable 5.2, 2026-11-14). Ungranted user proven over HTTP; switched-off proven at the function (see §8).

```gherkin
Scenario: A switched-off person is refused
  Given a valid token for a person who has been switched off
  Then the address refuses them

Scenario: A person without the Intelligent Layer is refused
  Given a valid token for a person without that grant
  Then the address refuses them

Scenario: A brand-new sign-up gets nothing
  Given someone signs up today and uses their token
  Then the address refuses them, because a new sign-up has no grants
```

**Build notes.** Call `usr/assert_module_access` with module `intelligence`; pass `or_module: ""`
explicitly. ⚠️ The last scenario holds only while new sign-ups get no grants. **PADM-2 (D-5) will
give a new account's admin all three modules** — story 04 must be done before PADM-2 ships.

### US-SEC-3-04 — A caller only reaches their own account's maps
**Status:** 📋 Not started — **handed to COP-1 stories 02 and 03**, tracked here so it is not lost.

```gherkin
Scenario: Another account's map is "not found"
  Given a valid, granted caller from account A
  When they call a tool with a map that belongs to account B
  Then the answer is "not found", the same as for a map that does not exist

Scenario: Maps made through a tool belong to the caller
  When a caller creates a map through a tool
  Then its owner and account are the caller's, never 0
```

### US-SEC-3-05 — Refusals are visible, and cannot flood the log
**Status:** 📋 Not started.

```gherkin
Scenario: A refused connection shows on Health
  When the address refuses a caller
  Then Health shows it, with a reason code

Scenario: A thousand refusals do not write a thousand rows
  When the address is hammered with no token
  Then at most a handful of rows are written per hour
```

**Build notes.** No `redis.*` on this plan — count recent rows with `db.query … count` before
writing, cutoff computed into a `var` first (the OBS-1 pattern in `apis/ops/1_ops_event_POST.xs`).

### US-SEC-3-06 — The door cannot be quietly opened again
**Status:** 🟡 Probe written and passing; local files match live. Not yet run on a schedule.

```gherkin
Scenario: A probe proves the door is shut
  Then a script calls the address with no token and fails loudly if any tool is listed

Scenario: The local files match live
  Then the trigger files in the repo are the same as the live trigger
  And the "temporarily disabled" comment is gone from all of them
```

**Build notes.** `tests/sec3_probe.py`, same style as `Epic-22/tests/sec2_probe.py`. Add it to the
list of probes run before a release. A nightly check would be better; that is a follow-up.

---

## 5. Governance

| Area | Rule |
|---|---|
| Tables | None |
| Validation | Refusal message is friendly and says nothing about whether a token "almost" worked |
| Error codes | `E-SEC-020` sign in to use these tools · reuse `E-USR-005` (switched off) and `E-USR-006` (not granted). Add `E-SEC-020` to `errorCatalog.json`, feature `SEC-3` (check the number is free first) |
| Events | Refused connection (capped, story 05). Passes are **not** logged — this runs on every connection |
| Rollback | Re-push the trigger with the check commented out. Reversible in one push — and it reopens the hole |

## 6. Counter-measures

| Risk | Counter-measure |
|---|---|
| The founder's own assistant is cut off | Told before the push; reconnect steps in story 02 |
| The check passes everyone because the caller is read from the wrong place | A no-token call is run right after every push; it must be refused |
| The check refuses everyone | A token call is run right after; if it fails, keep the door shut and fix forward — never reopen to "test" |
| The in-app chat breaks | It does not use this address; one chat message is sent after the push to prove it |
| A local file with the old comment is pushed later | Both local copies updated in the same change (story 06) |
| Maps already made with owner 0 | Listed, not rewritten here (COP-1 story 01) |

## 7. Test plan

| ID | Kind | What |
|---|---|---|
| FT-SEC-3-01 | HTTP | No token: `tools/list` and `tools/call` refused |
| FT-SEC-3-02 | HTTP | Invalid token refused |
| FT-SEC-3-03 | HTTP | Valid, granted token: list works, one read works |
| FT-SEC-3-04 | HTTP | Switched-off user and ungranted user refused |
| FT-SEC-3-05 | HTTP | Flood of refusals → capped rows |
| FT-SEC-3-06 | Browser | In-app map chat still answers |
| REG | Suites | USR-2 matrices unchanged (15/15, 16/16) |

## 8. Test results (2026-11-14, Fable 5.2)

**Before the fix:** with no token, `tools/list` returned 21 tools and `get_map 226` returned the map.

**After the fix** — `tests/sec3_probe.py`, real HTTP, test account 13 only:

| ID | Check | Result |
|---|---|---|
| FT-SEC-3-01 | No token: 0 tools, `get_map` → "Tool get_map not found" | ✅ |
| FT-SEC-3-02 | Made-up token, in the header and on the address | ✅ refused both ways |
| FT-SEC-3-03 | Granted, switched-on test user: 21 tools, map read — header and address | ✅ both ways |
| FT-SEC-3-04a | Test user without the Intelligent Layer | ✅ refused (0 tools) |
| FT-SEC-3-04b | Switched-off test user | 🟡 `usr/assert_module_access` refuses them (run directly: Access Denied). **Not run over HTTP** — a switched-off user cannot get a token any more (SEC-2), so there was none to present |
| FT-SEC-3-05 | Flood of refusals | Not run — refusals for a missing/bad token write **no** rows yet (story 05) |
| FT-SEC-3-06 | In-app map chat still answers | **Not run in a browser.** By reading: api 52 runs the agent directly and does not use this address |
| REG | `npm test` | ✅ 789/789. USR-2 matrices not re-run (nothing they cover was touched) |

**Confirmed side effect:** the founder's "xano-journey-map" connector now answers
"Tool list_maps not found" — it connects without a token. Expected; fix in §9.

**Seen again, as predicted:** the granted test user (account 13) could read map 226, which is not
theirs. That is story 04 — tenancy inside the tools — and is **still open**.

## 9. What was pushed, and how to reconnect an assistant

| Pushed to Xano (workspace 1) | What |
|---|---|
| Trigger 2 "Auth Gate" (updated) | The gate. Returns an empty tool list unless `usr/mcp_caller` says yes |
| Function 307 `usr/mcp_caller` (new) | Reads the token, checks it, asks `usr/assert_module_access` |
| API 630 `GET auth/whoami` (new, Authentication group) | "Whose token is this?" — id only, writes no event |

Scratch functions 305 and 306 were created and deleted. Test tokens were kept in a scratch file
and removed.

**Two things learned about this platform (worth a CLAUDE.md line):**
- Inside an MCP server trigger, `$auth.id` and `$input.auth` are **empty even with a valid Bearer
  token**. The trigger can read `$env.$http_headers` and `$env.$request_uri`, so the token has to
  be checked by hand. `mcp_server { auth = "user" }` is a syntax error.
- A failed `precondition` in the trigger gives the caller a confusing platform error
  ("Undefined array key toolset"). Returning `tools: []` is the clean way to refuse: nothing is
  listed and every call answers "Tool … not found".

**To reconnect an outside assistant (the founder does this; nobody else handles the token):**
1. Sign in to Emgram and create a token with `automation_api_token/generate` (1 year).
2. In the assistant's connector settings, either add the header `Authorization: Bearer <token>`,
   or — if it only takes an address — use `…/x2/mcp/ju0Zh1JM/mcp/stream?token=<token>`.
3. Reconnect. The tools reappear. Do not paste the token into a chat, a map or a document.

**Rollback:** none that is safe. Reopening the door is the hole.
