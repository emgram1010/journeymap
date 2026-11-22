# US-SCALE-1-03 — Map items match outside products

**Epic:** SCALE-1 · **Size:** S · **Model:** Sonnet 5.5 · **Status:** 📋 Not built
**Depends on:** US-SCALE-1-01, DEMAND-1 story 03

## Description

An order line says "product 8f3a…, quantity 14". The map's Items row says "chair-adult, 1.2
minutes each". Nothing connects the two, so an incoming order cannot be timed. The owner needs
to link each outside product to a catalog item once, and to see which products still have no link.

The first source is Booqable, but the link is generic: a source system name and that system's
own id. A second order source later needs no new table.

## User story

**As** the owner, **I want** my catalog items linked to the products in my order system, **so
that** order lines land on the right item and get the right time.

## Acceptance criteria

```gherkin
Scenario: link a product to an item
  When I link product "8f3a" from "booqable" to the item "chair-adult"
  Then order lines for that product become lines for "chair-adult"

Scenario: several products, one item
  Given two product ids that are both adult chairs
  Then both can link to "chair-adult"

Scenario: one product, one item
  When I try to link a product that is already linked
  Then I am asked to move the link, not create a second one

Scenario: an unlinked product arrives
  Given an order line whose product has no link
  Then the job is still created
  And the product is added to the "Products to link" list with its name and how often it has appeared
  And the job shows "no time set" for that line

Scenario: I link it afterwards
  Then future orders use the link
  And jobs not yet started can be refreshed with one press; started jobs are not changed

Scenario: products that are not items
  Given a line for a delivery fee or a deposit
  When I mark it "not an item"
  Then it stops appearing in "Products to link" and is ignored on future orders

Scenario: the item is switched off in the catalog
  Then its links stay, and orders for it show "no time set" with the reason

Scenario: another account
  Then it never sees or uses my links
```

- New table (additive), suggested `item_external_ref`: account, source system, external id,
  external name (as last seen), item id (0 = not an item / ignore flag), created by, last seen at.
- Unique index on (account, source system, external id).
- The lookup is one function, called by the webhook path and by the tools.

## Counter-measures

| Risk | Prevention |
|---|---|
| Two people link the same product at once and make two rows | The unique index decides; the second save is told "already linked" |
| A link points at another account's item | The server checks the item is in the caller's account on every save |
| A wrong link silently mistimes every order | The link list shows item, time per unit and last 5 orders that used it, so a wrong link is visible. Changing a link is logged with before and after |
| Unlinked products go unnoticed | Counted on the Health page; the list is sorted by how often each appeared |
| The product name is treated as trusted text | Stored as plain text, trimmed, length-capped, shown escaped (it comes from outside) |
| Refreshing jobs after a new link changes live work | Only jobs with no started task; EST-1's freeze rule is the check |
| The table is built for one vendor | No vendor name in any column or function name; `source_system` is a value, not a design |
| Bundles or kits arrive as one line | **Assumed:** the order fetch returns component lines. If it returns only the bundle, the bundle is linked like any product and flagged in this story's open item |
| Deleting a catalog item orphans its links | Catalog delete is refused while links exist, with a count in the message |
| Bulk import of links half-applies | Query, then loop by id inside one transaction; report counts, then re-query to confirm |

## Governance

- **Errors (suggested):** `E-SCALE-010` product already linked · `E-SCALE-011` item not found
  in this account · `E-SCALE-012` item has links and cannot be deleted.
- **Events:** `item_link.created`, `.moved` (before and after), `.removed`, `.marked_not_an_item`;
  `order_line.unlinked_product` (warning, with source and external id).
- **Delete behaviour:** links are removed only by the owner; removing one never touches past jobs.

## Tests (write first)

| ID | Test |
|---|---|
| T-SCALE-03-1 | Linked product becomes the right line |
| T-SCALE-03-2 | Two products to one item both work |
| T-SCALE-03-3 | Second link for one product refused; move works and is logged |
| T-SCALE-03-4 | Unlinked product: job created, listed, flagged |
| T-SCALE-03-5 | "Not an item" hides it and it is ignored afterwards |
| T-SCALE-03-6 | Refresh updates unstarted jobs only |
| T-SCALE-03-7 | Second account cannot see or use the links |
| T-SCALE-03-8 | Two parallel saves of the same product leave one row |
| T-SCALE-03-9 | A real order, with links set, estimates to the hand calculation |
