# US-SAFE-1-03 — An admin resets a member's password

**Epic:** SAFE-1 · **Size:** S · **Model:** Opus 5.5 (sign-in path)
**Status:** ✅ Built and verified live 2026-11-21. Not built: revoking earlier sign-ins; an in-app notice list (see epic Test Results)
**Decisions:** D-2 ✅ **any team admin** may reset (2026-11-21). D-8 ✅ **no email for now**
(2026-11-21): the link is shown to the admin, who hands it over. D-1 ✅ **1 hour, single use** (2026-11-21).
**Approved by the founder 2026-11-21 (D-9):** admins reset members, only the owner resets
admins, and platform support resets the owner.

## Findings before build (2026-11-21, read-only)

| Finding | Effect |
|---|---|
| **There was no "owner" in Emgram.** `user.role` is only `admin` or `member`; `account` has no owner field | ✅ **D-10 (2026-11-21): owner role added.** Side table `account_owner` (table 167), one owner per account, no endpoint writes it; seeded account 2 → Jav (user 2). Lookup `usr/account_rank` (function 416) answers owner / admin / member / AI, verified live on 5 users |
| **Owner shown on Manage users (2026-11-21).** `GET account/owner` (endpoint 671) + `mergeTeam`/`roleLabel`; the owner's row reads "Owner" (gold shield) and has no role dropdown. Verified over real HTTP and in the app with a temporary test owner (removed after). Tests UT-SAFE-03-OWN-1..4 pass; `npm test` 1021/1021 | ✅ Server guard added the same day: `usr/assert_owner_untouched` (417) in the four admin endpoints, E-SAFE-008 |
| AI members are only recognised through `ai_identity` (the copilot). **Eli Claude (user 34) has a normal email and no `ai_identity` row**, so today it reads as a person | Until AIM-1 marks AI logins, the reset refuses `ai_identity` users only. AIM-1 story 00 must mark Eli |
| No user has `is_platform_admin` on, so "platform support" has nobody behind it today | Jav, the only owner, can still recover through the existing "forgot password" flow (it mails the instance owner). Support-reset stays a manual step |
| **An AI login must never get a reset link.** The copilot's address is `.invalid` on purpose so nobody can sign in as it and act outside the tool gate (`admin/user_update`, E-COP-012) | AI members are refused. They never need a password: they connect with access tokens (AIM-1 story 03) |
| `Getting Started Template/generate_magic_link` already makes a 1-hour, single-use link and replaces any earlier one | Reused as is; matches D-1 |
| `reset/magic-link-login` and `reset/update_password` exist | Reused for the person's side |
| Neither web app has a reset screen; the only link points at Xano's demo page | A small "set your password" page is needed in the app |
| `reset/request-reset-link` is public, says "No user found for that email" (reveals who has an account) and mails the link to the instance owner | Out of scope; flagged as a separate security fix |
| Xano sign-in tokens cannot be revoked one by one | "Old sign-ins stop working" needs a check on every signed-in endpoint; proposed as its own follow-up story |

## Description

Once a member account exists, nobody can get that member back in. "Forgot my password" needs an
inbox, and Emgram does not send email for now (D-8). An AI member has no inbox at all.

So the reset works like a locksmith, not a letter: an admin makes a **one-time link**, sees it
**once**, and gives it to the person directly (in person, by phone, in a chat). The person opens
it and sets a new password. The admin never sees or sets the password itself.

The pieces to build on already exist: a one-time sign-in link (`reset/magic-link-login`), an
update-password endpoint, `Getting Started Template/generate_magic_link` (writes a hashed token
and sends no email), and the admin guard `usr/assert_team_admin`.

Showing the link on screen makes one risk bigger: whoever holds it can take over that account.
With email, the link could only reach the account's own inbox. Without email, the guardrails
below carry that weight.

## User story

**As** a team admin, **I want** to make a one-time reset link for a member and hand it to them,
**so that** nobody, person or AI, is locked out, and I never learn their password.

## Acceptance criteria

```gherkin
Scenario: reset a member
  Given I am a team admin and Dana is a member (not an admin) of my account
  When I choose "Reset password" for Dana and confirm
  Then a one-time link is shown to me once, with a copy button, and never again
  And it works once and expires (D-1)
  And Dana must set a new password before doing anything else
  And I never see or set the password

Scenario: reset an AI member
  Given the member's login is marked as an AI
  Then the reset is refused: "AI members don't use passwords. Re-issue its access token instead."
  And nothing is written except a refused event

Scenario: reset another admin (D-9)
  Given the person is an admin
  When an admin who is not the owner chooses "Reset password"
  Then it is refused: "Only the account owner can reset another admin."
  And when the owner does it, the link is shown once to the owner

Scenario: the owner loses their own password (D-9)
  Then no one in the account can reset the owner
  And the owner is pointed to platform support, who confirm who they are before making a link

Scenario: the owner is told (in-app, no email)
  When any reset link is made in the account
  Then the owner gets an in-app notice: who made it, for whom, when
  And the person reset gets an in-app notice the next time they sign in

Scenario: someone who is not an admin
  When they try to reset another member
  Then they are refused with a friendly message and nothing is written

Scenario: a member of another account
  When an admin of account A asks to reset a member of account B
  Then the answer is "Person not found" (never "not allowed", which would confirm they exist)

Scenario: the link is used
  When the person sets a new password with the link
  Then the link stops working
  And every earlier sign-in for that person stops working

Scenario: the link expires, is replaced or is cancelled
  Given a link past its time, a newer link for the same person, or one the admin cancelled
  Then it is refused: "This link has expired. Ask an admin for a new one."

Scenario: resetting myself
  When an admin picks themselves
  Then they are told to change their password from their own profile instead

Scenario: a switched-off member
  Then the reset is refused: "Switch this person back on first."
```

## Counter-measures

| Risk | Prevention |
|---|---|
| An admin takes over another admin's or the owner's account with a shown link | Admins reset members only; only the owner resets an admin; nobody in the account resets the owner |
| The link is copied by someone looking over the admin's shoulder | Shown once, short life (D-1), single use; the admin can cancel it; the owner is notified in-app |
| An admin changes a person's email, then resets, to take the account | A reset within 24 hours of an email change on that account is refused, and the owner is told |
| A stolen admin session resets many people | At most 5 resets per admin per hour (count rows in `event_log` since a cutoff held in a `var`; `redis.*` is not available on this plan) |
| The link ends up in logs | Store only the hash. Never write the link or token to `event_log`, an error message or a server-logged URL |
| Old sessions keep working after the reset | **To verify:** Xano tokens are self-contained. If they cannot be revoked, add a `password_changed_at` time on a side table and refuse tokens issued before it. Riskiest part; prove it over real HTTP |
| The existing "forgot my password" screen still promises an email | **To check:** if `reset/request_reset_link` sends or promises email, the screen says "Ask an admin to reset your password" instead (no email sent) |
| Two links for one person are live at once | Making a new link retires the earlier one |
| Adding a column to `user` drops its text validators | No `updateTableSchema` on `user`. Side table only, with its own GET if the screen needs it |
| A second copy of the "is this an admin?" rule | Reuse `usr/assert_team_admin` |
| The admin closes the page before copying the link | They make a new one; the old one is retired. Nothing is shown twice |

## Governance

- **Errors (in the catalog):** `E-SAFE-002` too many resets · `E-SAFE-004` switched off ·
  `E-SAFE-005` email changed in the last 24 hours · `E-SAFE-006` only the owner resets an admin ·
  `E-SAFE-007` the owner cannot be reset here · `E-SAFE-008` only the owner changes the owner ·
  `E-SAFE-009` not yourself · `E-SAFE-010` not an AI. "Not an admin" reuses `E-USR-001`
  (one code, one meaning). 001 and 003 were not needed: a dead link is refused by the existing
  sign-in-with-link endpoint, and the page shows one sentence for every dead link.
- **Events:** `user.password_reset_link_made` (who, for whom, when), `…_link_cancelled`,
  `…_completed`, `…_refused` (code), `…_owner_notified`. No token, link or password in any event.
- **Notices:** in-app only (D-8).
- **Delete behaviour:** unused links are removed when the person is deleted.

## Tests (write first)

| ID | Test |
|---|---|
| T-SAFE-03-1 | Admin makes a link for a member: shown once, works once, then refused |
| T-SAFE-03-2 | Non-admin refused, no row written |
| T-SAFE-03-3 | Cross-account returns "not found" |
| T-SAFE-03-4 | Expired, replaced and cancelled links refused |
| T-SAFE-03-5 | A sign-in token issued before the reset is refused after it (real HTTP) |
| T-SAFE-03-6 | Sixth reset in an hour refused |
| T-SAFE-03-7 | No event row contains the token (search the rows) |
| T-SAFE-03-8 | Non-owner admin resetting an admin refused; owner allowed; nobody resets the owner |
| T-SAFE-03-9 | Reset within 24 hours of an email change refused |
| T-SAFE-03-10 | Owner gets an in-app notice for every link made |
| T-SAFE-03-11 | No email is sent at any step |
| T-SAFE-03-12 | UI: button for admins only; link shown once with copy (**Assumed:** screen change on Manage users) |
