// O8 (2026-10-17) — The maps a plan in THIS ACCOUNT could attach. USR-2 (2026-11-14): the body moved, unchanged, into journey/attachable_maps, which the planner group's copy of this endpoint also calls — one rule, two doors. The Planner app now reads the planner-group copy; this one stays for anything still pointed here.
query journey_map_attachable verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    function.run "journey/attachable_maps" {
      input = {user_id: $auth.id}
    } as $out
  }

  response = $out
}
