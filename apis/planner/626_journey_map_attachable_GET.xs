// USR-2 (2026-11-14) — the maps a plan in this account could attach, served from the PLANNER group. Same list as journey-map endpoint 578 (both call journey/attachable_maps), but behind the Planner gate instead of the Intelligent Layer gate, so a Planner-only person can still attach a map. Static single-segment path: no dynamic root-level GET exists in this group to shadow it (checked).
query journey_map_attachable verb=GET {
  api_group = "planner"
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
