# Error message style (VAL-1, US-VAL-1-05)

Every message a user sees comes from the error catalog
(`webapp/protype-2/src/ops/errorCatalog.json`). Write every
`user_message` to this standard. The catalog's own lint
(`errorCatalog.test.ts`) enforces the length and banned-word part of
this automatically; the rest is judgement.

## The rule

**Say what happened. Say how to fix it. Nothing else.**

| Do | Don't |
|---|---|
| "This is required." | "Validation failed for field 'name'." |
| "That name is already used." | "Unique constraint violation." |
| "Someone else changed this. Reload to see the latest." | "Conflict: stale updated_at." |
| "We couldn't save your changes. Your work is still here." | "Internal server error." |

## Five checks before you write one

1. **No jargon.** No "validation", "constraint", "null", "exception", no
   internal table or field names, no error codes in the sentence itself
   (the code is shown separately, as the Reference).
2. **Never blame the user.** "This is required," not "You forgot to fill
   this in." A tone of fact, not fault.
3. **One sentence where possible.** A second sentence is for the fix,
   only when it isn't obvious from the first.
4. **No stack traces, no raw technical text, ever.** This is enforced:
   `errorCatalog.ts`'s `JARGON_PATTERNS` lint blocks stack-frame shapes,
   raw `E-XXX-NNN` codes inside the message, and `TypeError` /
   `ReferenceError` / etc. appearing in `user_message`.
5. **Keep the founder's three audiences straight** (`owner` field in the
   catalog): `user` messages assume no technical knowledge at all;
   `product_manager` entries (`what_happened`, `likely_cause`,
   `fix_hint`) can name features and screens but still no code;
   `engineer` entries are the only place a table or function name
   belongs, and even there, stay plain.

## Length

`user_message`: aim for under 80 characters. The lint
(`errorCatalog.test.ts`) doesn't hard-fail on length today, but a
message that doesn't fit on one line in a small dialog is too long —
split the "why" into `what_happened` instead of stuffing it into the
sentence the user sees.

## Worked example

Bad: `"ERROR_CODE_ACCESS_DENIED: user 42 lacks is_platform_admin for account 7"`

Good:
```json
"user_message": "You don't have access to this.",
"what_happened": "Someone tried to read or change something that belongs to a different account.",
"likely_cause": "A stale link or bookmark pointing at another account's data, or a bug passing the wrong id.",
"fix_hint": "Check the Health page timeline for this Reference to see which entity and account were involved."
```

The user sees only the first line. You, on the Health page, see all four.
