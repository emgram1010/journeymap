// EXC-1 (US-EXC-1-03 / -08) — The line split: which counts stay on the
// parent job and which go to the child. PURE: reads nothing, writes
// nothing. The backend twin of
// `webapp/protype-2/src/exceptions/splitLines.ts`; both run over
// `src/fixtures/exception-split-golden.json` (FT-EXC-1-01 / UT-EXC-1-01..04).
//
// RULES, per moved line, in this order, first bad line wins:
//   1. the item is on the parent order            — E-EXC-005
//   2. the item is not listed twice               — E-EXC-007
//   3. integer quantity, 1 ≤ q ≤ the parent line  — E-EXC-006
// A line moved in full is REMOVED from the parent (D-4) and listed in
// `removed`. Output order follows the PARENT's lines. Empty `moved` is a
// whole-job exception: nothing moves, ok = true.
//
// ⚠️ BUILT IN PHASES ON PURPOSE (same reason as jobs/tasks_from_version):
// a `conditional` inside a `foreach` whose condition reads a var
// `var.update`d earlier in the same iteration silently drops the
// branch's writes (CLAUDE.md). So every per-line verdict is computed
// UNCONDITIONALLY into a field of an object, and the later loops branch
// only on fields of their loop item.
function "exceptions/split_lines" {
  input {
    json parent_lines
    json moved
  }

  stack {
    var $parent_by_id {
      value = {}
    }

    foreach ($input.parent_lines) {
      each as $pl {
        var $pl_key {
          value = $pl.item_type_id|to_text
        }

        var.update $parent_by_id {
          value = $parent_by_id|set:$pl_key:$pl
        }
      }
    }

    // ── Phase 1: a verdict per moved line, no branching ────────────────
    var $seen {
      value = {}
    }

    var $verdicts {
      value = []
    }

    var $moved_by_id {
      value = {}
    }

    foreach ($input.moved ?? []) {
      each as $m {
        // Junk-proof number checks (FT-EXC-1-G01): JSON-encode first and
        // match digits only. A raw comparison on "two" or {} throws "Not
        // numeric." (a 500, not a friendly refusal), and to_int would turn
        // "2" into 2 where the TypeScript twin refuses the string. Encoded,
        // a numeric string keeps its quotes and fails the pattern on both
        // sides.
        var $m_id_json {
          value = ($m.item_type_id ?? null)|json_encode
        }

        var $m_id_ok {
          value = "/^[1-9][0-9]{0,9}$/"|regex_matches:$m_id_json
        }

        var $m_key {
          value = ($m_id_ok == true) ? $m_id_json : "not-an-id"
        }

        var $m_parent {
          value = $parent_by_id|get:$m_key:null
        }

        var $m_found {
          value = ($m_parent != null)
        }

        var $m_dup {
          value = (($seen|get:$m_key:null) != null)
        }

        var.update $seen {
          value = $seen|set:$m_key:true
        }

        var $m_q_json {
          value = ($m.quantity ?? null)|json_encode
        }

        var $m_q_int {
          value = "/^[0-9]{1,9}$/"|regex_matches:$m_q_json
        }

        var $m_q {
          value = ($m_q_int == true) ? ($m_q_json|to_int) : 0
        }

        var $m_parent_q {
          value = $m_parent.quantity ?? 0
        }

        var $m_q_ok {
          value = ($m_q_int == true && $m_q >= 1 && $m_q <= $m_parent_q)
        }

        var $m_code {
          value = ($m_found == false) ? "E-EXC-005" : (($m_dup == true) ? "E-EXC-007" : (($m_q_ok == true) ? "" : "E-EXC-006"))
        }

        array.push $verdicts {
          value = {item_type_id: $m.item_type_id ?? 0, code: $m_code}
        }

        var.update $moved_by_id {
          value = $moved_by_id|set:$m_key:$m_q
        }
      }
    }

    // ── Phase 2: the first bad line, branching only on the loop item ───
    var $bad {
      value = []
    }

    foreach ($verdicts) {
      each as $v {
        conditional {
          if ($v.code != "") {
            array.push $bad {
              value = $v
            }
          }
        }
      }
    }

    var $bad_count {
      value = $bad|count
    }

    var $first_bad {
      value = {item_type_id: 0, code: ""}
    }

    conditional {
      if ($bad_count > 0) {
        var.update $first_bad {
          value = $bad|first
        }
      }
    }

    // ── Phase 3: the split, in the parent's order ──────────────────────
    var $rows {
      value = []
    }

    foreach ($input.parent_lines) {
      each as $p {
        var $p_key {
          value = $p.item_type_id|to_text
        }

        var $p_moved {
          value = ($moved_by_id|get:$p_key:null) ?? 0
        }

        array.push $rows {
          value = {
            item_type_id: $p.item_type_id
            item_key    : $p.item_key ?? ""
            child_q     : $p_moved
            rest_q      : $p.quantity - $p_moved
          }
        }
      }
    }

    var $parent_after {
      value = []
    }

    var $child_lines {
      value = []
    }

    var $removed {
      value = []
    }

    foreach ($rows) {
      each as $r {
        conditional {
          if ($r.child_q > 0) {
            array.push $child_lines {
              value = {item_type_id: $r.item_type_id, item_key: $r.item_key, quantity: $r.child_q}
            }
          }
        }

        conditional {
          if ($r.rest_q > 0) {
            array.push $parent_after {
              value = {item_type_id: $r.item_type_id, item_key: $r.item_key, quantity: $r.rest_q}
            }
          }

          else {
            array.push $removed {
              value = $r.item_type_id
            }
          }
        }
      }
    }

    // A refused split returns EMPTY arrays, never the half-computed ones
    // above (they can hold a negative remainder) — so no caller can
    // write them by mistake.
    conditional {
      if ($bad_count > 0) {
        var.update $parent_after {
          value = []
        }

        var.update $child_lines {
          value = []
        }

        var.update $removed {
          value = []
        }
      }
    }
  }

  response = {
    ok          : ($bad_count == 0)
    code        : $first_bad.code
    item_type_id: $first_bad.item_type_id
    parent_after: $parent_after
    child_lines : $child_lines
    removed     : $removed
  }
}
