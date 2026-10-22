// ORD-1 (US-ORD-1-03) — Reorder a map's columns: send every stage id, in
// the order you want them.
//
// Thin on purpose. Ownership is journey/assert_map_owner (SEC-1); the
// exact-permutation rule, the E-ORD-001 refusal and the 1..n write all
// live in journey/apply_stage_order, so the buttons, insert-at-position
// and the AI tool cannot disagree about what a legal order is.
//
// Only display_order changes; keys never do (ORD-1 story 01). A reorder
// changes the map's content hash, so the "draft changes" badge lights up
// on its own — no versioning work here (decided 2026-10-19).
query "journey_stage/reorder/{journey_map_id}" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id filters=min:1
    json stage_ids
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/assert_map_owner" {
      input = {
        journey_map_id   : $input.journey_map_id
        caller_account_id: $actor.account_id
        user_id          : $auth.id
        step             : "reorder_stages"
      }
    } as $guard

    function.run "journey/apply_stage_order" {
      input = {
        journey_map_id: $input.journey_map_id
        stage_ids     : $input.stage_ids
        user_id       : $auth.id
        account_id    : $actor.account_id
        step          : "reorder_stages"
        correlation_id: $input.correlation_id
      }
    } as $applied

    db.patch journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
      data = {updated_at: "now", last_interaction_at: "now"}
    } as $map_touch

    function.run "ops/log_event" {
      input = {
        feature       : "ORD-1"
        step          : "reorder_stages"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id    : $actor.account_id
        entity_type   : "journey_map"
        entity_id     : $input.journey_map_id
        correlation_id: $input.correlation_id
        message       : "Columns reordered."
      }
    } as $_logged
  }

  response = {
    order                 : $applied.order
    journey_map_updated_at: $map_touch.updated_at
  }
}
