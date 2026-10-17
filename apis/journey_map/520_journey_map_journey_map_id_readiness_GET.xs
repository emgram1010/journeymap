// PUB-1 (US-PUB-1-01) — The server's own answer to "is this map ready?".
//
// Read-only and safe to poll: it builds the same snapshot a publish would
// freeze and runs the same gate a publish would run, so what the UI shows
// here and what the publish endpoint decides can never disagree.
//
// `blockers` and `gate_failures` are the same list under two names:
// `blockers` matches the shape US-PUB-1-01 specifies, `gate_failures`
// matches the earlier publishing initiative's contract (D-39). Both are
// the gate's view — readiness plus the real-title rule.
query "journey_map/{journey_map_id}/readiness" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "You don't have access to this map. (E-PUB-004)"
    }

    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: $input.journey_map_id}
    } as $snapshot_result

    function.run "pub/evaluate_gate" {
      input = {snapshot: $snapshot_result.snapshot}
    } as $gate
  }

  response = {
    ready        : $gate.ready
    blockers     : $gate.gate_failures
    warnings     : $gate.warnings
    ready_count  : $gate.ready_count
    total        : $gate.total
    gate_failures: $gate.gate_failures
  }
}
