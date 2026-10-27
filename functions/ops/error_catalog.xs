// OBS-1 (US-OBS-1-03) — Backend copy of the error catalog.
//
// The authoritative, human-edited catalog lives in
// webapp/protype-2/src/ops/errorCatalog.json (used by the frontend for
// inline field errors and the Health page). This function is a small
// backend copy of the SAME entries, used only where the backend itself
// needs catalog text at runtime (currently: build_diagnostic_bundle and
// group_issues, so a bundle/issue can show its owner and suggested fix
// without a round trip to the frontend).
//
// IMPORTANT — keep in sync by hand: whenever a new error code is added to
// the frontend catalog, add the same entry here too. There is no shared
// build step between the Xano backend and the Vite frontend in this repo,
// so this sync is manual. Only OBS-1's own codes are listed for now;
// later epics add their codes to both places as they are built.
function "ops/error_catalog" {
  input {
  }

  stack {
    var $catalog {
      value = {}
        |set:"E-OBS-001":{
          code         : "E-OBS-001"
          feature      : "OBS-1"
          user_message : "You don't have access to this page."
          what_happened: "A non-admin user (or an unauthenticated request) tried to reach an ops/* endpoint or the Health page."
          likely_cause : "The caller's user record does not have is_platform_admin set to true."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "If this user should be a platform admin, set user.is_platform_admin = true directly in the database. There is no UI for this on purpose."
        }
        |set:"E-OBS-002":{
          code         : "E-OBS-002"
          feature      : "OBS-1"
          user_message : "Too many reports were sent in a short time, so we slowed down."
          what_happened: "The client event endpoint's rate limit (20 per minute per user) was hit, usually from a screen stuck in an error loop."
          likely_cause : "A front-end bug is repeatedly failing and reporting the same error."
          owner        : "engineer"
          severity     : "info"
          fix_hint     : "Check the Health page's issue list for the feature/step that is flooding, and fix the underlying front-end error."
        }
        |set:"E-GOV-001":{
          code         : "E-GOV-001"
          feature      : "GOV-1"
          user_message : "You don't have access to this."
          what_happened: "Someone tried to read or change something that belongs to a different account."
          likely_cause : "A stale link or bookmark pointing at another account's data, or a bug passing the wrong id."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Check the Health page timeline for this Reference to see which entity and account were involved."
        }
        |set:"E-GOV-002":{
          code         : "E-GOV-002"
          feature      : "GOV-1"
          user_message : "Those two things belong to different accounts, so they can't be linked."
          what_happened: "An action tried to connect two records that live in different accounts."
          likely_cause : "A picker or form offered an option from outside the current account."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Find the two entity ids on the Health page timeline for this Reference, then check which screen offered the cross-account option."
        }
        |set:"E-GOV-003":{
          code         : "E-GOV-003"
          feature      : "GOV-1"
          user_message : "This can't be done while it's in its current state."
          what_happened: "An action was attempted on something whose status doesn't allow it, for example editing a plan that is already live."
          likely_cause : "The screen was showing an out-of-date status, usually because it hadn't been reloaded."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the page to see the current status."
        }
        |set:"E-GOV-004":{
          code         : "E-GOV-004"
          feature      : "GOV-1"
          user_message : "This has been archived, so it can't be changed."
          what_happened: "A write was attempted against an archived record."
          likely_cause : "The item was archived in another tab or by someone else since this screen was opened."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload to confirm it is archived. Archived items are kept for history on purpose."
        }
        |set:"E-GOV-005":{
          code         : "E-GOV-005"
          feature      : "GOV-1"
          user_message : "Someone else changed this. Reload to see the latest."
          what_happened: "Two people edited the same record, and the second save was refused so it couldn't overwrite the first."
          likely_cause : "Two tabs or two people working on the same plan at the same time."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload and redo the change. Nothing was lost: the refused save was never written."
        }
        |set:"E-CAT-001":{
          code         : "E-CAT-001"
          feature      : "CAT-1"
          user_message : "Use a short id with letters, numbers and hyphens, like chair-resin."
          what_happened: "An item type or method key was saved with fewer than 2 or more than 40 characters, or with a character other than a lowercase letter, digit or hyphen, or starting with a hyphen."
          likely_cause : "The key was typed by hand instead of using the suggested one, or included spaces or punctuation."
          owner        : "user"
          severity     : "info"
          fix_hint     : "The key is what rates and orders reference later, so keep it short and plain. Edit the suggested key rather than typing a new one from scratch."
        }
        |set:"E-CAT-002":{
          code         : "E-CAT-002"
          feature      : "CAT-1"
          user_message : "You already have an item with that id."
          what_happened: "An item type was created with a key that another item type in this account already uses."
          likely_cause : "The same item was added twice, often under a slightly different label."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Find the existing item in the list and edit it instead of creating a second one."
        }
        |set:"E-CAT-003":{
          code         : "E-CAT-003"
          feature      : "CAT-1"
          user_message : "Give it a name up to 80 characters, with no HTML."
          what_happened: "An item type or method label was saved empty, over 80 characters, or containing an HTML tag."
          likely_cause : "The name field was left blank, or text was pasted in from somewhere that included formatting tags."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Paste as plain text and keep the name to a sentence or less."
        }
        |set:"E-CAT-004":{
          code         : "E-CAT-004"
          feature      : "CAT-1"
          user_message : "Pick a unit: each, set or pair."
          what_happened: "An item type's unit was left blank or set to something other than each, set or pair."
          likely_cause : "The unit dropdown was left at its empty default, or a value outside the three choices was sent."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Most items are 'each'. Use 'set' when one line should cover a whole group of pieces, like a game."
        }
        |set:"E-CAT-005":{
          code         : "E-CAT-005"
          feature      : "CAT-1"
          user_message : "This is used by a map or a published version. Deactivate it instead."
          what_happened: "A delete was refused because the item type or method is already referenced by a map's item list or a published version's rate card."
          likely_cause : "The item or method has already been put to use, so removing it would orphan whatever points at it."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Deactivate it from the catalog list instead. It disappears from new maps but published versions and history keep working."
        }
        |set:"E-CAT-006":{
          code         : "E-CAT-006"
          feature      : "CAT-1"
          user_message : "You can't change another account's catalog."
          what_happened: "A create, update, deactivate or delete was attempted against an item type or method that belongs to a different account."
          likely_cause : "A stale id, or a request built outside the normal screen."
          owner        : "user"
          severity     : "warn"
          fix_hint     : "Reload the catalog screen and use the item or method from your own account's list."
        }
        |set:"E-CAT-007":{
          code         : "E-CAT-007"
          feature      : "CAT-1"
          user_message : "Pick a map from your own account."
          what_happened: "A method's sub-journey map was set to a map id that does not exist, or belongs to a different account."
          likely_cause : "A stale map list, or an id from somewhere else."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the map picker. Only maps this account owns can be a method's sub-journey."
        }
        |set:"E-CAT-008":{
          code         : "E-CAT-008"
          feature      : "CAT-1"
          user_message : "You already have a method with that id."
          what_happened: "A method was created with a key that another method in this account already uses."
          likely_cause : "The same method was added twice, often under a slightly different label."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Find the existing method in the list and edit it instead of creating a second one."
        }
        |set:"E-CAT-009":{
          code         : "E-CAT-009"
          feature      : "CAT-1"
          user_message : "Keep the size label short, up to 20 characters."
          what_happened: "An item type's size label was saved with more than 20 characters."
          likely_cause : "A full description was typed where a short grouping label like '6ft' or 'large' was expected."
          owner        : "user"
          severity     : "info"
          fix_hint     : "The size label is only used to group and report on items — it never affects any calculation, so keep it brief."
        }
        |set:"E-CAT-010":{
          code         : "E-CAT-010"
          feature      : "CAT-1"
          user_message : "Keep the external reference up to 60 characters, with no HTML."
          what_happened: "An item type's external reference (the booking or inventory SKU) was saved over 60 characters or containing an HTML tag."
          likely_cause : "Something other than a plain SKU or code was pasted into the field."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Paste the SKU or code only, as plain text."
        }
        |set:"E-CAT-011":{
          code         : "E-CAT-011"
          feature      : "CAT-1"
          user_message : "Pick an active method from your own account, or leave it blank."
          what_happened: "An item type's default method was set to a method id that does not exist, belongs to a different account, or has been deactivated."
          likely_cause : "A stale method list, a deactivated method, or an id from somewhere else."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the method list. The default method only seeds a suggestion when this item is first used on a map — it can always be overridden there."
        }
        |set:"E-CAT-012":{
          code         : "E-CAT-012"
          feature      : "CAT-1"
          user_message : "Only an account admin can deactivate, reactivate or delete a catalog entry."
          what_happened: "A non-admin tried to change an item type or method's active status, or delete one."
          likely_cause : "Any account member can create an item type or method, but turning one off, back on, or removing it needs an admin."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Ask an account admin to make the change, or edit a field other than the active status yourself."
        }
        |set:"E-ITM-001":{
          code         : "E-ITM-001"
          feature      : "ITEM-1"
          user_message : "This map already has an Items row."
          what_happened: "A second Items row was requested for a map that already has one."
          likely_cause : "The Add Items Row button was clicked twice, or two tabs tried to create it at once."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the map -- the existing Items row is already there, at the bottom."
        }
        |set:"E-ITM-002":{
          code         : "E-ITM-002"
          feature      : "ITEM-1"
          user_message : "Add that item to this map's item list first."
          what_happened: "An Items cell line, or the map's chosen-item list itself, referenced an item that is inactive, belongs to a different account, or was never added to this map's item list."
          likely_cause : "The item picker is out of date, or an item was deactivated in the catalog after this map chose it."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Open Choose items on the Items row and add it, or pick an item already in the list."
        }
        |set:"E-ITM-003":{
          code         : "E-ITM-003"
          feature      : "ITEM-1"
          user_message : "Choose per order, per unit or per flagged unit."
          what_happened: "An Items cell was saved with a scaling choice other than the three allowed values."
          likely_cause : "A stale form state, or a direct API call with a typo in the value."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reopen the cell editor and pick one of the three options."
        }
        |set:"E-ITM-004":{
          code         : "E-ITM-004"
          feature      : "ITEM-1"
          user_message : "Enter minutes for one item, like 2.5, or leave it empty for now."
          what_happened: "A line's minutes-per-unit was negative, over 1440 (a full day), or had more than 2 decimal places."
          likely_cause : "A typo, or pasting a value that wasn't really a minutes figure."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Enter a number between 0 and 1440 with at most 2 decimal places, or leave the box empty."
        }
        |set:"E-ITM-005":{
          code         : "E-ITM-005"
          feature      : "ITEM-1"
          user_message : "Pick a method from your catalog."
          what_happened: "A line named a method that is inactive, belongs to a different account, or does not exist."
          likely_cause : "The method list is out of date, or a method was deactivated after a cell line was already using it."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the method list and pick an active one."
        }
        |set:"E-ITM-006":{
          code         : "E-ITM-006"
          feature      : "ITEM-1"
          user_message : "That item already has a line for that method here."
          what_happened: "An Items cell was saved with two lines naming the same item and the same method."
          likely_cause : "The add-a-line control was used twice for the same item/method pair instead of editing the existing line."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Remove the duplicate line, or pick a different method for the second one."
        }
        |set:"E-ITM-007":{
          code         : "E-ITM-007"
          feature      : "ITEM-1"
          user_message : "The Items row can't own a stage -- pick a person or team row."
          what_happened: "A stage's owner was set to the Items row, which is a perspective (what's in the job), not an actor that can be accountable for a stage."
          likely_cause : "The owner picker listed every row, including the Items row, without filtering it out."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Pick an actual actor row as the owner. If the Items row shows up in an owner picker, that picker needs to exclude template_key = items-v1."
        }
        |set:"E-ITM-008":{
          code         : "E-ITM-008"
          feature      : "ITEM-1"
          user_message : "The Items row doesn't do planned work; that switch stays off."
          what_happened: "Something tried to turn on \"does planned work\" for the Items row, which never performs planned work by design."
          likely_cause : "The planned-work toggle was shown for the Items row when it should have been hidden."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "The Items row should never show a planned-work toggle. If it does, that control needs to exclude template_key = items-v1."
        }
        |set:"E-ITM-009":{
          code         : "E-ITM-009"
          feature      : "ITEM-1"
          user_message : "The Items row is removed with its own Remove row button."
          what_happened: "A generic row-delete path (journey/remove_lens: the matrix's row delete or an AI tool) was asked to delete the Items row, which would skip its own cleanup and the published-rates guard."
          likely_cause : "A screen or AI tool offered the generic row delete on the Items row."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Delete the Items row with its Remove row button (endpoint 603). If a screen or AI tool offered the generic delete on the Items row, that control needs to exclude template_key = items-v1."
        }
        |set:"E-ITM-010":{
          code         : "E-ITM-010"
          feature      : "ITEM-1"
          user_message : "Edit an Items cell with the Items cell editor."
          what_happened: "The generic cell update (endpoint 44) was asked to write an Items cell's item lines, which would skip validate_items_cell and link reconciliation."
          likely_cause : "A screen or tool saved an Items cell through the generic cell editor instead of the Items cell editor."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Save Items cells through the Items cell editor (endpoint 605). Status and lock changes through the generic update are still allowed."
        }
        |set:"E-EST-001":{
          code         : "E-EST-001"
          feature      : "EST-1"
          user_message : "Enter how many, from 1 to 9999."
          what_happened: "An order line's quantity was outside 1-9999 or not a whole number."
          likely_cause : "A typo, or an empty quantity box."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Enter a whole number from 1 to 9999."
        }
        |set:"E-EST-002":{
          code         : "E-EST-002"
          feature      : "EST-1"
          user_message : "That item has been deactivated. Pick another or reactivate it in Settings → Items."
          what_happened: "An order line named an item that has been deactivated in the catalog."
          likely_cause : "The item was deactivated after this order was started, or the picker is out of date."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reactivate the item in Settings → Items, or pick a different one for this line."
        }
        |set:"E-EST-003":{
          code         : "E-EST-003"
          feature      : "EST-1"
          user_message : "That item isn't on this map. Add it to the map's Items row and publish a new version."
          what_happened: "An order line named an item that the job's published version has no rate for on any stage — it was never part of this map's Items row, or belongs to a different account."
          likely_cause : "The item picker is out of date, or the item was never added to this map's Items row."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Open the map's Items row, add the item with a rate, publish a new version, then create a new order."
        }
        |set:"E-EST-004":{
          code         : "E-EST-004"
          feature      : "EST-1"
          user_message : "This work type doesn't track items. Add an Items row to the map and publish a new version."
          what_happened: "Order lines were submitted for a job whose map has no Items row at all."
          likely_cause : "The map was never set up to track item counts."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Add an Items row to the map, give it rates, publish a new version, then create a new order against it."
        }
        |set:"E-EST-005":{
          code         : "E-EST-005"
          feature      : "EST-1"
          user_message : "This job isn't linked to a published version yet."
          what_happened: "A job's order lines were requested, but the job has no pinned published version."
          likely_cause : "A data problem — every job should be pinned to a version at creation."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Check how this job was created; it should always be pinned to a published version."
        }
        |set:"E-EST-006":{
          code         : "E-EST-006"
          feature      : "EST-1"
          user_message : "That item is already on this order — change its quantity instead."
          what_happened: "The same item appeared twice in one order-lines update."
          likely_cause : "The add-item control was used twice for the same item instead of editing its existing line."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Remove the duplicate line and update the quantity on the one that's left."
        }
        |set:"E-EST-007":{
          code         : "E-EST-007"
          feature      : "EST-1"
          user_message : "Work has started on this order, so its items are locked. Create a new order for the extra items."
          what_happened: "An order's lines were edited after at least one of its steps had already started."
          likely_cause : "Someone tried to change what's in an order that's already being worked."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Create a new order for any additional items — this order's estimate must not drift under live work."
        }
        |set:"E-RATE-001":{
          code         : "E-RATE-001"
          feature      : "RATE-1"
          user_message : "An item on this map was deactivated. Remove its line or reactivate it, then publish."
          what_happened: "Publish was refused because a rate on this map uses an item that has been deactivated in the catalog. A new version may not pin a rate for a dead item; older versions keep theirs."
          likely_cause : "The item was deactivated in the catalog after its line was added to the Items row."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Open the map's Items row, remove that item's line from every stage (or reactivate the item in the catalog), then publish again."
        }
        |set:"E-RATE-002":{
          code         : "E-RATE-002"
          feature      : "RATE-1"
          user_message : "This map has published rates. Set every stage to per order and publish again instead of removing the row."
          what_happened: "Removing the Items row was refused because at least one published version of this map carries rates."
          likely_cause : "Someone tried to delete the Items row after the map was published with rates."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Set every stage's Items cell to per order, then publish a new version. The old versions keep their rates, which is the honest history."
        }
        |set:"E-RATE-003":{
          code         : "E-RATE-003"
          feature      : "RATE-1"
          user_message : "A published version is missing rate rows."
          what_happened: "The nightly audit found a version whose stage_rate rows do not match the rates frozen in its snapshot."
          likely_cause : "A stage_rate row was deleted or added outside the publish path (a direct database edit or a restore gone wrong)."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Run ops/audit_rates to see which version. Re-materialize the missing rows from that version's snapshot.rates; never edit the snapshot itself."
        }
        |set:"E-EXC-001":{
          code         : "E-EXC-001"
          feature      : "EXC-1"
          user_message : "That job is finished or cancelled, so nothing can be sent from it or added under it."
          what_happened: "Someone tried to send part of a job to a linked map from a job that was already completed or cancelled, or to add a new job under a cancelled parent."
          likely_cause : "The job was closed between loading the screen and pressing Send, or the parent picked for a new job is cancelled."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the job. If the work really needs to go somewhere, add a new job for it."
        }
        |set:"E-EXC-002":{
          code         : "E-EXC-002"
          feature      : "EXC-1"
          user_message : "This step doesn't send work to that map. Add an exception link on the map and publish a new version — new jobs will have it."
          what_happened: "A send-to request named a map that the job's pinned version does not link to as an exception at this step's stage, or a map in another account."
          likely_cause : "The exception link was added to the live map after this job started (jobs keep the version they started with), or the request was built by hand."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Add the exception link on the map, publish a new version, and use it on jobs created after that. This job cannot gain the link."
        }
        |set:"E-EXC-003":{
          code         : "E-EXC-003"
          feature      : "EXC-1"
          user_message : "That map hasn't been published yet. Publish it, then try again."
          what_happened: "A send-to request pointed at a linked map that has no published version, so there is nothing to pin the new job to."
          likely_cause : "The linked map was created but never published. Readiness warned about this on the parent map (exception_map_unpublished)."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Open the linked map, publish a version, then send the work again."
        }
        |set:"E-EXC-004":{
          code         : "E-EXC-004"
          feature      : "EXC-1"
          user_message : "This work type doesn't track items, so you can't pick which ones to send. Send the whole step instead."
          what_happened: "Item counts were sent with a send-to request on a job whose map has no Items row."
          likely_cause : "The request included counts for a job that has none."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Send without counts. To track items, add an Items row to the map and publish a new version."
        }
        |set:"E-EXC-005":{
          code         : "E-EXC-005"
          feature      : "EXC-1"
          user_message : "That item isn't on this order."
          what_happened: "A send-to request listed an item that is not one of the job's order lines."
          likely_cause : "The order changed since the screen was loaded, or the request was built by hand."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reload the job and pick from the items shown."
        }
        |set:"E-EXC-006":{
          code         : "E-EXC-006"
          feature      : "EXC-1"
          user_message : "Enter how many to send, from 1 up to how many are on the order."
          what_happened: "A send-to request asked to move zero, a negative or fractional number, or more than the order holds of an item."
          likely_cause : "A typing mistake, or the order's count went down since the screen was loaded."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Enter a whole number between 1 and the count on the order."
        }
        |set:"E-EXC-007":{
          code         : "E-EXC-007"
          feature      : "EXC-1"
          user_message : "That item is listed twice — combine them."
          what_happened: "The same item appeared twice in one send-to request."
          likely_cause : "The item was added twice instead of raising its count."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Remove the duplicate and put the full count on one line."
        }
        |set:"E-EXC-008":{
          code         : "E-EXC-008"
          feature      : "EXC-1"
          user_message : "The linked map doesn't track items, so the counts can't go with the work. Add an Items row to it and publish, or send without counts."
          what_happened: "Counts were sent to a linked map whose latest published version has no Items row, so the new job could not hold them."
          likely_cause : "The linked map was built without an Items row."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Either send the step without counts, or add an Items row to the linked map, publish it, and try again."
        }
        |set:"E-EXC-009":{
          code         : "E-EXC-009"
          feature      : "EXC-1"
          user_message : "That parent job is in a different plan."
          what_happened: "A job was added with a parent job that does not exist, is in another account, or is in a different plan."
          likely_cause : "The parent id was copied from another plan, or the request was built by hand."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Pick a parent job from the same plan."
        }
        |set:"E-EXC-010":{
          code         : "E-EXC-010"
          feature      : "EXC-1"
          user_message : "Pick a reason."
          what_happened: "A send-to request had no reason, or one that is not on the fixed list (waiting on someone, missing information, something went wrong, other)."
          likely_cause : "The reason was left empty, or an old app version sent an unknown value."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Choose one of the four reasons and send again."
        }
        |set:"E-EXC-011":{
          code         : "E-EXC-011"
          feature      : "EXC-1"
          user_message : "Keep the note under 500 characters, with no HTML."
          what_happened: "A send-to request's note was longer than 500 characters or contained HTML."
          likely_cause : "A long paste, or copied formatting."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Shorten the note, or remove any formatting, and send again."
        }
        |set:"E-EXC-012":{
          code         : "E-EXC-012"
          feature      : "EXC-1"
          user_message : "The order changed while you were sending. Close this and try again."
          what_happened: "Another send (or an order edit) changed this job's lines between the checks and the save, so nothing was written."
          likely_cause : "Two people sent items from the same job at the same moment."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Reopen the job to see its current counts, then send again."
        }
        |set:"E-EXC-013":{
          code         : "E-EXC-013"
          feature      : "EXC-1"
          user_message : "This was already sent. Reopen the job to see it."
          what_happened: "A send-to request repeated one that had already saved (same request), so no second child job was made."
          likely_cause : "The first response was lost (a slow phone connection) and Send was tapped again. The app treats this as sent."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Nothing to do: the first send made the child job. Reopen the job to see it."
        }
        |set:"E-EXC-014":{
          code         : "E-EXC-014"
          feature      : "EXC-2"
          user_message : "We couldn't open that job just now. Try again."
          what_happened: "The job view failed to load the other job's steps."
          likely_cause : "A dropped connection or a server error."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "Try again. If it keeps happening, quote the Reference to support."
        }
        |set:"E-EXC-015":{
          code         : "E-EXC-015"
          feature      : "EXC-2"
          user_message : "That job isn't available any more."
          what_happened: "The job view asked for a job that no longer exists in this account."
          likely_cause : "The job belongs to another account, or the link is stale."
          owner        : "user"
          severity     : "info"
          fix_hint     : "Nothing to fix on the job you're on. Ask a planner if the sent work was moved."
        }
    }
  }

  response = $catalog

  test "contains the OBS-1 access-denied entry" {
    expect.to_equal ($response|get:"E-OBS-001.owner":null) {
      value = "engineer"
    }
  }

  test "contains the GOV-1 cross-account entry" {
    expect.to_equal ($response|get:"E-GOV-001.owner":null) {
      value = "engineer"
    }
  }

  test "contains the CAT-1 cross-account entry" {
    expect.to_equal ($response|get:"E-CAT-006.owner":null) {
      value = "user"
    }
  }

  test "contains the ITEM-1 owner-guard entry" {
    expect.to_equal ($response|get:"E-ITM-007.owner":null) {
      value = "engineer"
    }
  }

  test "contains the EXC-2 job-view-load-failure entry" {
    expect.to_equal ($response|get:"E-EXC-014.owner":null) {
      value = "engineer"
    }
  }
}
