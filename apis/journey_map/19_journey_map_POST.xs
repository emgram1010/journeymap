// Add a journey_map record owned by the signed-in caller.
//
// US-SEC-1-04 (2026-10-18) — WAS OPEN, AND TOOK ITS OWNER FROM THE
// BODY. Anyone could create a map with no login and stamp it with any
// `owner_user` and any `account_id` they liked — which means planting
// a map inside someone else's account, and creating rows that the new
// account-scoped list endpoints would then serve to that account as
// its own.
//
// OWNERSHIP NOW COMES FROM THE TOKEN, NEVER FROM THE BODY. `$auth.id`
// is the owner and the caller's own account is the account; both
// fields are still accepted by the dblink input (it mirrors the whole
// table) and both are deliberately ignored. This is the same rule
// `journey_map/create_draft` (endpoint 42) already follows — that is
// the real creation path, and this CRUD endpoint is the frontend's
// fallback when the business endpoint is not configured.
//
// FIXED HERE, PRE-EXISTING AND FOUND BY SECURING IT: the two date
// columns were written from `$input`, and an omitted optional `date`
// input does not exist at all — referencing it is a runtime
// "Unable to locate input: updated_at", not a null (CLAUDE.md; unlike
// text/int, which arrive as ""/0). The frontend's
// CreateDraftJourneyMapInput never sends either field, so this
// endpoint returned 500 on every call the app could make, and nobody
// noticed because the business endpoint normally answers first and the
// fallback swallows the error. Both are now "now", which is what a
// create means and what endpoint 42 already does.
query journey_map verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    dblink {
      table = "journey_map"
    }
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    db.add journey_map {
      enforce_hidden_fields = false
      data = {
        created_at         : "now"
        updated_at         : "now"
        title              : $input.title
        status             : $input.status
        owner_user         : $auth.id
        account_id         : $actor.account_id
        last_interaction_at: "now"
        settings           : $input.settings
      }
    } as $model
  }

  response = $model
}
