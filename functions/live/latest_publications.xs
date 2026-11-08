// REPUB-1 (US-REPUB-1-01) — The CURRENT publication for each timeline:
// one row per timeline, the one with the highest id.
//
// THE RULE LIVES HERE AND NOWHERE ELSE. Until REPUB-1, `plan_publication`
// could hold at most one row per timeline, and every reader leaned on
// that (`|first`, last-seen-wins maps). Republishing adds rows — old
// versions stay forever as history — so "which snapshot is current" is
// now a real question, and it must have exactly one answer in exactly
// one place (the same house rule that produced `log/next_status`).
// Highest id = latest insert = newest version; US-REPUB-1-02's explicit
// `version` column will agree with this ordering by construction.
//
// NO CONDITIONAL TOUCHES A VAR SET IN ITS OWN ITERATION. The max is
// folded into arithmetic with a bool|to_int (the `next_stage_key`
// pattern), rows are then TAGGED with `is_latest` in a second pass, and
// the only branch reads that field OFF THE LOOP ITEM in a third — the
// one branching shape CLAUDE.md marks reliable. Keys are prefixed "k:"
// so `|get` can never see an empty key, and the variable-key default
// bug is covered with `?? 0` (strict `??`, catches only real null).
//
// An empty `timeline_ids` yields an empty list, same as the `in $tl_ids`
// queries this replaces.
function "live/latest_publications" {
  input {
    int[] timeline_ids
  }

  stack {
    db.query plan_publication {
      where = $db.plan_publication.timeline_id in $input.timeline_ids
      return = {type: "list"}
    } as $pubs

    var $max_by_tl {
      value = {}
    }

    var $tkey {
      value = ""
    }

    var $cur {
      value = 0
    }

    var $gt {
      value = 0
    }

    var $best {
      value = 0
    }

    foreach ($pubs) {
      each as $p {
        var.update $tkey {
          value = "k:" ~ ($p.timeline_id|to_text)
        }

        var.update $cur {
          value = ($max_by_tl|get:$tkey:0) ?? 0
        }

        var.update $gt {
          value = ($p.id > $cur)|to_int
        }

        var.update $best {
          value = $cur + (($p.id - $cur) * $gt)
        }

        var.update $max_by_tl {
          value = $max_by_tl|set:$tkey:$best
        }
      }
    }

    var $tagged {
      value = []
    }

    var $is_latest {
      value = 0
    }

    foreach ($pubs) {
      each as $p {
        var.update $tkey {
          value = "k:" ~ ($p.timeline_id|to_text)
        }

        var.update $cur {
          value = ($max_by_tl|get:$tkey:0) ?? 0
        }

        var.update $is_latest {
          value = ($p.id == $cur)|to_int
        }

        array.push $tagged {
          value = {row: $p, is_latest: $is_latest}
        }
      }
    }

    var $latest {
      value = []
    }

    foreach ($tagged) {
      each as $t {
        conditional {
          if ($t.is_latest == 1) {
            array.push $latest {
              value = $t.row
            }
          }
        }
      }
    }
  }

  response = {publications: $latest}
}
