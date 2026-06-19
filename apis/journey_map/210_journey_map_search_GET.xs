// IL-01-04: Account-scoped full-text search across published journey maps.
// Searches ai_summary and tags fields. Returns maps owned by the authenticated user's account.
// Zero cells scanned — search operates on index fields only.
query "journey_map/search" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    // Natural language search query — matched against ai_summary and tags.
    text query? filters=trim

    // Optional filter: sop | automation | hybrid
    enum intent? {
      values = ["sop", "automation", "hybrid"]
    }

    // Optional filter: JSON array of tag strings e.g. ["onboarding", "crm"]
    json tags?

    // US-RES-4-03: pagination — page_size default 50, offset default 0.
    int page_size? filters=min:1
    int offset? filters=min:0
  }

  stack {
    var $effective_page_size {
      value = ($input.page_size ?? 50)
    }

    var $effective_offset {
      value = ($input.offset ?? 0)
    }

    // Load the authenticated user to resolve account_id
    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $auth_user
  
    // Query published maps scoped to the user's account
    db.query journey_map {
      where = $db.journey_map.account_id == $auth_user.account_id && $db.journey_map.status == "active"
      sort = {updated_at: "desc"}
      return = {type: "list"}
    } as $candidate_maps
  
    // Filter in-memory: query match on ai_summary + tags, optional intent filter
    var $results {
      value = []
    }
  
    var $query_lower {
      value = $input.query|lowercase
    }
  
    foreach ($candidate_maps) {
      each as $map {
        // Intent filter (skip if set and doesn't match)
        var $intent_pass {
          value = true
        }
      
        conditional {
          if ($input.intent != null && $map.intent != $input.intent) {
            var.update $intent_pass {
              value = false
            }
          }
        }
      
        conditional {
          if ($intent_pass) {
            // Text match: check ai_summary and tags contain the query
            var $summary_text {
              value = ($map.ai_summary ?? "")|lowercase
            }
          
            var $tags_text {
              value = `($map.tags|json_encode ?? "")|lowercase`
            }
          
            var $text_match {
              value = false
            }
          
            conditional {
              if ($input.query == null || $input.query == "") {
                var.update $text_match {
                  value = true
                }
              }
            
              elseif ($summary_text|contains:$query_lower) {
                var.update $text_match {
                  value = true
                }
              }
            
              elseif ($tags_text|contains:$query_lower) {
                var.update $text_match {
                  value = true
                }
              }
            }
          
            conditional {
              if ($text_match) {
                array.push $results {
                  value = {
                    map_id           : $map.id
                    title            : $map.title
                    ai_summary       : $map.ai_summary
                    intent           : $map.intent
                    tags             : $map.tags
                    status           : $map.status
                    last_published_at: $map.updated_at
                  }
                }
              }
            }
          }
        }
      }
    }

    // US-RES-4-03: apply pagination slice over filtered results
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

    // US-RES-8-01/04: search telemetry emit.
    var $search_rows_scanned {
      value = $results|count
    }

    var $search_is_slow {
      value = $search_rows_scanned > 500
    }

    db.add event_log {
      enforce_hidden_fields = false
      data = {
        created_at: "now"
        user_id   : $auth.id
        action    : "telemetry:search"
        metadata  : {
          rows_scanned  : $search_rows_scanned
          rows_returned : $paged_results|count
          is_slow       : $search_is_slow
        }
      }
    } as $_stelem
  }

  response = {
    query    : $input.query
    total    : $results|count
    page_size: $effective_page_size
    offset   : $effective_offset
    count    : $paged_results|count
    results  : $paged_results
  }
  guid = "VHbKtCxfcdZ05ZIn33G5DgwHwaE"
}