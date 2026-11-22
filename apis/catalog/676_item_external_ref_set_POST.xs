// SCALE-1 story 03 — a person links an outside product to a catalog item, marks it "not an item", or clears the link. All rules live in items/set_external_ref. A product already linked elsewhere answers move_needed first and changes nothing until move is true.
query item_external_ref_set verb=POST {
  api_group = "catalog"
  auth = "user"

  input {
    int ref_id?
    text source_system? filters=trim
    text external_id? filters=trim
    text external_name? filters=trim
    int item_type_id?
    bool not_an_item?
    bool move?
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "items/set_external_ref" {
      input = {account_id: ($actor.account_id ?? 0), user_id: $auth.id, ref_id: $input.ref_id, source_system: $input.source_system, external_id: $input.external_id, external_name: $input.external_name, item_type_id: $input.item_type_id, not_an_item: $input.not_an_item, move: $input.move}
    } as $r
  }

  response = $r
}
