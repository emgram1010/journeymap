// IL-00-06: MCP tool — list journey maps for the authenticated scope.
// US-RES-4-01/02/03: tenant-scoped via owner_user, in-memory filtered, paginated.
// NOTE: intent is stored in settings JSON (not a column) — cannot be pushed to DB where.
// NOTE: architecture_id, status, map_level are in-memory; the new composite index on
//       journey_map(account_id, status, map_level, journey_architecture) makes the
//       DB scan bounded by tenant even though predicates are applied post-fetch.
tool list_maps {
  instructions = "List journey maps. Optionally filter by architecture_id, intent (sop|automation|hybrid), status (draft|active|archived), or map_level (architecture|actor-journey|atomic). Returns an array of { id, title, intent, status, map_level, last_interaction_at }."

  input {
    int architecture_id?
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }

    enum status? {
      values = ["draft", "active", "archived"]
    }

    // LA-4: filter by Intelligence Layer map level.
    // Use map_level='atomic' to find L3 maps valid for leakage analysis.
    enum map_level? {
      values = ["architecture", "actor-journey", "atomic"]
    }

    // US-RES-4-03: pagination — page_size default 50, offset default 0.
    int page_size? filters=min:1
    int offset? filters=min:0
  }

  stack {
    // US-RES-4-01: scope to the authenticated user's own maps (tenant isolation).
    // owner_user == $auth.id is the narrowest safe scope for the tool runtime.
    db.query journey_map {
      where  = $db.journey_map.owner_user == $auth.id
      sort   = {last_interaction_at: "desc"}
      return = {type: "list"}
    } as $all_maps

    var $effective_page_size {
      value = ($input.page_size ?? 50)
    }

    var $effective_offset {
      value = ($input.offset ?? 0)
    }

    var $results {
      value = []
    }

    foreach ($all_maps) {
      each as $m {
        var $pass {
          value = true
        }

        conditional {
          if ($input.architecture_id != null && $m.journey_architecture != $input.architecture_id) {
            var.update $pass {
              value = false
            }
          }
        }

        conditional {
          if ($input.intent != null && $m.intent != $input.intent) {
            var.update $pass {
              value = false
            }
          }
        }

        conditional {
          if ($input.status != null && $m.status != $input.status) {
            var.update $pass {
              value = false
            }
          }
        }

        conditional {
          if ($input.map_level != null && $m.map_level != $input.map_level) {
            var.update $pass {
              value = false
            }
          }
        }

        conditional {
          if ($pass) {
            array.push $results {
              value = {
                id                 : $m.id
                title              : $m.title
                intent             : $m.intent
                status             : $m.status
                map_level          : $m.map_level
                last_interaction_at: $m.last_interaction_at
              }
            }
          }
        }
      }
    }

    // US-RES-8-05: cross-tenant canary — count any map that slipped past the owner_user filter.
    // Expected value: always 0. Non-zero means the scoping where clause regressed.
    var $cross_tenant_count {
      value = 0
    }

    foreach ($all_maps) {
      each as $tm {
        conditional {
          if ($tm.owner_user != $auth.id) {
            var.update $cross_tenant_count {
              value = $cross_tenant_count + 1
            }
          }
        }
      }
    }

    // US-RES-4-03: pagination — walk results to produce the paged slice.
    var $total {
      value = $results|count
    }

    var $paged_results {
      value = []
    }

    var $cursor {
      value = 0
    }

    foreach ($results) {
      each as $item {
        var $paged_count {
          value = $paged_results|count
        }

        conditional {
          if ($cursor >= $effective_offset && $paged_count < $effective_page_size) {
            array.push $paged_results {
              value = $item
            }
          }
        }

        var.update $cursor {
          value = $cursor + 1
        }
      }
    }

    // US-RES-8-01: emit read telemetry to event_log.
    // US-RES-8-04: is_slow flags full-table-scale reads (rows_scanned > 500).
    // US-RES-8-05: cross_tenant_leak should always be 0 — non-zero = canary failure.
    var $rows_scanned {
      value = $all_maps|count
    }

    var $is_slow {
      value = $rows_scanned > 500
    }

    db.add event_log {
      enforce_hidden_fields = false
      data = {
        created_at: "now"
        user_id   : $auth.id
        action    : "telemetry:list_maps"
        metadata  : {
          rows_scanned      : $rows_scanned
          rows_returned     : $paged_results|count
          is_slow           : $is_slow
          cross_tenant_leak : $cross_tenant_count
        }
      }
    } as $_telem
  }

  response = {
    total    : $total
    page_size: $effective_page_size
    offset   : $effective_offset
    count    : $paged_results|count
    results  : $paged_results
  }
}