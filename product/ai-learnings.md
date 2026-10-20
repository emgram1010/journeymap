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
