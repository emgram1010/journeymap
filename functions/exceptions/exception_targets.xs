// EXC-1 (US-EXC-1-01) — The database facts readiness needs about each
// `exception` link on a map: is the target published, does it have an
// Items row, is it in the same architecture. pub/evaluate_readiness stays
// pure over its inputs (same pattern ITEM-1 used for Items cells), so
// these facts are resolved here and passed in as `exception_targets`.
//
// Reads the links from the SNAPSHOT the caller built (the same thing a
// publish would freeze), not from journey_link directly, so readiness and
// the eventual version agree about which links exist.
//
// `has_items_row`: the target's LATEST PUBLISHED version decides when it
// has one (that is what a spawned child job would be pinned to); a
// never-published target falls back to its live Items row.
//
// One entry per exception link, in snapshot order. De-duplication per
// (stage, target) is the readiness rule's job, not this function's.
// No conditional reads a var updated in the same loop iteration
// (CLAUDE.md): every fact is computed unconditionally and pushed.
function "exceptions/exception_targets" {
  input {
    int journey_map_id filters=min:1
    json snapshot
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $source

    var $source_arch {
      value = $source.journey_architecture ?? 0
    }

    var $stage_labels {
      value = {}
    }

    foreach ($input.snapshot.stages ?? []) {
      each as $st {
        var $st_key {
          value = "k:" ~ $st.key
        }

        var.update $stage_labels {
          value = $stage_labels|set:$st_key:($st.label ?? $st.key)
        }
      }
    }

    var $targets {
      value = []
    }

    foreach ($input.snapshot.links ?? []) {
      each as $link {
        conditional {
          if ($link.link_type == "exception" && $link.target_map_id > 0) {
            db.get journey_map {
              field_name = "id"
              field_value = $link.target_map_id
            } as $target

            db.query journey_map_version {
              where = $db.journey_map_version.journey_map_id == $link.target_map_id
              sort = {journey_map_version.version_no: "desc"}
              return = {type: "list"}
            } as $target_versions

            db.query journey_lens {
              where = $db.journey_lens.journey_map == $link.target_map_id && $db.journey_lens.template_key == "items-v1"
              return = {type: "count"}
            } as $live_items_rows

            var $version_count {
              value = $target_versions|count
            }

            var $latest {
              value = $target_versions|first
            }

            var $latest_schema {
              value = $latest.snapshot.schema_version ?? 0
            }

            var $is_published {
              value = ($version_count > 0)
            }

            var $has_items {
              value = ($is_published == true) ? ($latest_schema >= 2) : ($live_items_rows > 0)
            }

            var $target_arch {
              value = $target.journey_architecture ?? 0
            }

            // Prefixed: `|get:""` returns the WHOLE object (CLAUDE.md).
            var $label_key {
              value = "k:" ~ ($link.stage_key ?? "")
            }

            var $stage_label {
              value = $stage_labels|get:$label_key:null
            }

            array.push $targets {
              value = {
                stage_key        : $link.stage_key
                stage_label      : $stage_label ?? $link.stage_key
                lens_key         : $link.lens_key ?? ""
                target_map_id    : $link.target_map_id
                target_title     : $target.title ?? "that map"
                published        : $is_published
                has_items_row    : $has_items
                same_architecture: ($target_arch == $source_arch)
              }
            }
          }
        }
      }
    }
  }

  response = $targets
}
