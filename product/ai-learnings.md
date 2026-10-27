# AI session learnings

My own notes on how to work on this project well. Not domain material
(that's `product/learnings/`) and not XanoScript gotchas (those belong
in `CLAUDE.md`). This is about **how I get things wrong here, and what
to do instead.**

Started 2026-10-18, after a session where the same few mistakes
repeated often enough to be a pattern rather than bad luck.

---

## 1. A feature means full stack

**What happened.** Asked to "enable soft delete and then the option of
hard delete", I built the backend, shipped it, and handed back a list:
no Restore in the UI, no way to see deleted maps, no hard-delete
option, and four confirm dialogs now saying *"this cannot be undone"*
when it could. I presented that as findings. It was unfinished work,
and I'd left the app telling the user the opposite of the truth.

**The rule.** Before calling a feature done, walk it as a user: can
they **do** it, **see** it, and **undo** it from the screen? Does any
existing text now lie? Sibling entities count — soft delete for maps
implies soft delete for architectures.

**The trap to avoid.** I had just been corrected for executing without
approval, and over-corrected into "do the minimum slice and ask
again". Those are different things:

- Confirm before **destroying data or pushing something irreversible**.
- Do **not** confirm before **finishing work already asked for**.

## 2. Verify at the layer the user touches, not the layer I changed

**What happened.** W7 was meant to grey out unpublished maps in the
picker. I changed the endpoint, tested the endpoint, and it was
correct — the picker was still broken, because a *different* filter
upstream (`status === 'active'`) hid every draft map anyway. I even
wrote a comment claiming "unpublished maps are returned, not filtered
out", which was false the moment I wrote it.

**The rule.** Verification happens at the **outermost** layer, against
**real data in this account**. Not "the endpoint returns the right
field" but "the dropdown shows the right options".

**Corollary.** A comment that states observable behaviour is a claim.
It needs a test or a live check for that exact sentence.

## 3. Open the browser — it is the cheapest bug-finder here

Three real bugs in about fifteen minutes, *after* everything was green
and committed: a popover clipped off-screen, the map picker hiding
every draft, and a form that refused to submit after switching plans.
None of them were findable by reading code or running the suite.

`CLAUDE.md`'s build protocol is backend-shaped — tests, endpoints,
events. It has no step that says *look at it*. There should be one.

## 4. The dangerous bugs are the silent ones

The three worst found this session all gave a **plausible wrong
answer** with no error:

- "Today" computed in UTC, so a performer's work vanished at 5pm local.
- An agent with no login: schedule and publish a whole day, nobody ever
  sees it.
- `AuthContext` clearing a good token on *any* failed check, including
  a request aborted by navigating away.

**The question to ask on every change:** *if this is wrong, what does
the screen show?* If the answer is "something plausible", it is not
finished — add the distinguishing signal.

## 5. Check the registry before inventing an identifier

I reached for `E-SCHED-002` and `E-SCHED-003` for two new failures.
Both already meant something else. Nothing in the build would have
caught it; I found it by grepping the catalog by hand, which is luck,
not process. Then, fixing it, I changed each **message** and left the
**logged code** on the old value — so the user would see one code and
the Health page would record another.

Both are now guarded by tests. The general rule: **before inventing a
code, path, table id or name, grep for it.**

## 6. A test that skips is not a test that passes

One of my own E2E specs skipped silently on every run because it raced
a reload and read the loading spinner as "not empty". In a summary
line it is indistinguishable from green.

## 7. Don't trust my own earlier claims

Twice this session I had to correct myself: once misreading git output
("local main is behind" — it was 8 commits ahead), once reporting a
decision as "taken as recommended" when the check had never been
built. **Re-read the actual artifact before repeating a claim about
it** — including a lesson from an earlier epic, which I applied from
memory and got half-right, reintroducing the same bug twice in one
component.

## 8. Fixing the finding is better than reporting it

When an audit turns up something real — orphaned rows, a dead
endpoint, a lying dialog — the useful output is the fix, not a
well-written description of the problem. Report what could not be
fixed and why, not a list of everything observed.

## 9. "I looked and it isn't there" is not the same as "it doesn't exist"

Three times in Epic-8 I stated a confident negative that one more
query would have disproved:

- I called `ai/tool/mutate_structure`'s `reorder_stages` dead code
  from reading it. A scratch function reproducing the loop showed it
  works.
- I told the founder there were **no test users** and that creating
  some was a decision they had to make, and wrote it into the epic as
  a blocker. There were five, in five different accounts, left by
  AUTH-1, GOV-1, DEL-1 and PLN-9. I had searched for *one* email from
  the Playwright specs, found it missing, and generalised from that to
  the whole table.
- I wrote in an endpoint comment that a call with no filter "returns
  an empty list exactly as before". It returns 400. The validator was
  visible in the schema I had already read.

Each one cost real work: the first produced a retraction, the second
told the founder they were blocked when they were not, the third put
a false statement into code where someone would later trust it.

The pattern is the same every time: **the evidence for a negative was
the absence of something in a narrow lookup.** A negative claim needs
the query that would have found it — list the table, not one row;
check the count, not one id. If that query has not been run, the
honest form is "I did not find X", not "X does not exist".

---

## A REQUIRED input makes your own validation unreachable (USR-1, 2026-10-22)

`admin/user_create` was written with `text name` / `text email` /
`text password` — required, as the three things you obviously cannot
create a person without. Underneath each one sat a precondition with a
friendly sentence and a catalogued code (`E-USR-011`, `E-USR-012`).

Not one of them could ever fire. Xano validates required inputs
**itself, before the stack runs and before auth is even checked**, so a
blank name came back as:

```
HTTP 400 {"code":"ERROR_CODE_INPUT_ERROR","message":"Missing param: name"}
```

No error code, no sentence the admin can act on, nothing the Health
page can explain, and a `""` treated as missing rather than as blank.
The endpoint's own careful validation was dead code from the moment it
was written.

Found by probing the live endpoint with a blank field — not by reading
it, which is the point. **The epic already claimed those codes worked.**

**The rule:** if an input has a precondition of its own, declare it
**optional**. An omitted optional text input arrives as `""`, which is
exactly what the precondition tests for, and the refusal is then the
endpoint's own — code, wording and log line. Required inputs are for
values with no friendlier refusal available than Xano's.

This is the same family as the existing `?? fallback` and
`!= null` traps: the engine answers first, in its own words, and the
code written downstream never gets a turn.

---

## `db.del` on a row that is not there is not a no-op (USR-1, 2026-10-22)

It raises `ERROR_CODE_NOT_FOUND` with an **empty message** — no code, no
sentence, nothing to look up in the catalog.

`admin/user_delete` destroys two rows: the person's `user_status` row
and their `user` row, together in a `db.transaction`. But a
`user_status` row only exists for somebody whose status has been
touched — **absence of a row means active**, which is the entire design
of that side table. So for the ordinary case, the first `db.del` found
nothing, threw a bare 404, and the transaction correctly rolled the
whole delete back.

The result was an endpoint that returned

```
HTTP 404 {"code":"ERROR_CODE_NOT_FOUND","message":""}
```

and deleted nobody, ever, while every refusal path around it worked
perfectly. The transaction did its job. The delete simply never
happened.

**Found on the very first real delete.** Reading the code would not
have shown it: the two `db.del` calls look symmetrical, and nothing in
the docs says a delete requires a match.

**The rule:** before `db.del` on anything whose existence is optional —
and a side table row is always optional, that is what a side table is —
count it first and wrap the delete in a `conditional`. Do not reason
about whether the row "should" be there.

**Two things confirmed working while fixing it:** a `conditional` nests
inside a `db.transaction`, and its condition may read a `var` computed
before the transaction block (the silent-discard trap needs a loop,
which this is not).

---

## `error_type = "input"` pushes cleanly and then fails at runtime

**USR-2, 2026-10-23.** A `precondition` written as:

```xs
precondition ($keys.valid == true) {
  error_type = "input"
  error = "We don't recognise that module. (E-USR-007)"
}
```

pushed with no parse error and then threw, on every call, with:

```
Param: error_type - Input "input" is not one of the allowable values.
ERROR_CODE_INPUT_ERROR
```

The precondition never refused the thing it exists to refuse — it raised an
unrelated error instead, and the catalogued message never appeared. The
correct value is **`inputerror`**.

The values actually in use across this codebase, counted: `notfound` (189),
`inputerror` (169), `accessdenied` (86), `badrequest` (5), `unauthorized` (1).
`input` appeared twice and both were mine, written the same hour.

**The lesson is not "remember the spelling".** It is that `error_type` is
validated at RUNTIME and not at push time, exactly like `exception_policy` on
a middleware, which silently stores `"silent"` for any value it does not
recognise. A guard whose refusal path has never been executed is a guard with
an untested branch, and the untested branch is the one that matters. Smoke-test
the REFUSAL, not just the success.

---

## A revoke that erases who granted it — and the `output` list that would have hidden the fix

**USR-2, 2026-10-23.** `user_module_access` keeps a `granted` bool rather than
deleting the row, and the table's own header says why: *"revoking by deleting
the row would throw away who granted it and when."*

The first version of `admin/user_module_access` then threw it away anyway. It
seeded all four audit columns before branching:

```xs
var $granted_by { value = 0 }
var $granted_at { value = null }
var $revoked_by { value = 0 }
var $revoked_at { value = null }
```

and let the grant branch fill the first pair and the revoke branch the second.
Every revoke therefore patched `granted_by_user_id` back to `0` and
`granted_at` to null. The endpoint returned 200, the UI showed the right
thing, and the row quietly lost half its history. It was caught only by
reading the row back out of the table after the call — not by the response,
which was correct.

The fix is to seed each pair from the row that already exists and overwrite
only the pair the call is about.

**The second half is the part worth remembering.** The lookup that feeds those
defaults was:

```xs
output = ["id", "granted"]
```

A column left out of `output` comes back **absent**, so
`$existing|get:"granted_by_user_id":0` would have returned its default `0` —
and the fix would have read correctly, reviewed correctly, and done exactly
nothing. Whenever a value is read back in order to be written forward, check
that the read actually asked for it.
