// US-DEL-1-04 (2026-10-18) — What is orphaned, and what deleting it
// would cost. READ-ONLY. This function never writes anything.
//
// Deliberately a report before an action. The founder approved a dry
// run only, and the story's own acceptance criteria put the report
// first regardless — "the counts match the audit that found them",
// reviewed, and only then a decision. A cleanup that reports its own
// success without being checked is the OBS-1 heartbeat failure all
// over again: it ran every five minutes for eight hours, wrote
// nothing, and reported fine.
//
// 🔴 `journey_map_version` IS COUNTED BUT NEVER LISTED FOR DELETION.
// Orphaned versions are the reason a deleted map does not break live
// work — a job reads its instructions from the frozen snapshot. They
// are reported separately, under `protected`, so the number is
// visible and nobody mistakes it for something to tidy.
//
// PLAN AND TEMPLATE LINKS ARE NAMED, not just counted. A dead link
// means a real plan is pointing at a map that no longer exists, and
// the founder needs to know WHICH plan before agreeing to anything —
// if the map was deleted by mistake, that is the thread back to it.
//
// COUNTS EVERY MAP IN THE WORKSPACE, not just this account's. An
// orphan audit that only knew about one account would report another
// account's perfectly healthy rows as orphaned.
function "journey/orphan_report" {
  input {
  }

  stack {
    db.query journey_map {
      return = {type: "list"}
    } as $maps

    var $live {
      value = {}
    }

    var $k {
      value = ""
    }

    foreach ($maps) {
      each as $m {
        var.update $k {
          value = $m.id|to_text
        }

        var.update $live {
          value = $live|set:$k:1
        }
      }
    }

    var $hit {
      value = null
    }

    // ── content belonging to maps that no longer exist ──────────────
    db.query journey_stage {
      return = {type: "list"}
    } as $stages

    var $orphan_stages {
      value = 0
    }

    foreach ($stages) {
      each as $s {
        var.update $k {
          value = $s.journey_map|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            var.update $orphan_stages {
              value = $orphan_stages + 1
            }
          }
        }
      }
    }

    db.query journey_lens {
      return = {type: "list"}
    } as $lenses

    var $orphan_lenses {
      value = 0
    }

    foreach ($lenses) {
      each as $l {
        var.update $k {
          value = $l.journey_map|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            var.update $orphan_lenses {
              value = $orphan_lenses + 1
            }
          }
        }
      }
    }

    db.query journey_cell {
      return = {type: "list"}
    } as $cells

    var $orphan_cells {
      value = 0
    }

    foreach ($cells) {
      each as $c {
        var.update $k {
          value = $c.journey_map|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            var.update $orphan_cells {
              value = $orphan_cells + 1
            }
          }
        }
      }
    }

    // ── links from plans and templates, named ───────────────────────
    db.query planner_workspace_map {
      return = {type: "list"}
    } as $ws_links

    var $dead_plan_links {
      value = []
    }

    foreach ($ws_links) {
      each as $wl {
        var.update $k {
          value = $wl.journey_map_id|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            db.get planner_workspace {
              field_name = "id"
              field_value = $wl.workspace_id
            } as $ws

            array.push $dead_plan_links {
              value = {link_id: $wl.id, map_id: $wl.journey_map_id, plan: ($ws.name ?? "(unknown plan)")}
            }
          }
        }
      }
    }

    db.query plan_template_map {
      return = {type: "list"}
    } as $tpl_links

    var $dead_template_links {
      value = []
    }

    foreach ($tpl_links) {
      each as $tl {
        var.update $k {
          value = $tl.journey_map_id|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            db.get plan_template {
              field_name = "id"
              field_value = $tl.plan_template_id
            } as $tpl

            array.push $dead_template_links {
              value = {link_id: $tl.id, map_id: $tl.journey_map_id, template: ($tpl.name ?? "(unknown template)")}
            }
          }
        }
      }
    }

    // ── protected: counted, never proposed for deletion ─────────────
    db.query journey_map_version {
      return = {type: "list"}
    } as $versions

    var $orphan_versions {
      value = 0
    }

    foreach ($versions) {
      each as $v {
        var.update $k {
          value = $v.journey_map_id|to_text
        }

        var.update $hit {
          value = $live|get:$k:null
        }

        conditional {
          if ($hit == null) {
            var.update $orphan_versions {
              value = $orphan_versions + 1
            }
          }
        }
      }
    }

    var $total {
      value = $orphan_stages + $orphan_lenses + $orphan_cells + ($dead_plan_links|count) + ($dead_template_links|count)
    }
  }

  response = {
    mode                : "dry_run"
    nothing_was_deleted : true
    live_maps           : ($maps|count)
    would_delete        : {
      journey_stage        : $orphan_stages
      journey_lens         : $orphan_lenses
      journey_cell         : $orphan_cells
      planner_workspace_map: ($dead_plan_links|count)
      plan_template_map    : ($dead_template_links|count)
      total                : $total
    }

    plans_affected      : $dead_plan_links
    templates_affected  : $dead_template_links
    protected           : {
      journey_map_version: $orphan_versions
      why                : "Jobs read their instructions from these frozen snapshots. Deleting one would silently strip the steps from live and historical work."
    }
  }
}
