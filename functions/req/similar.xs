// REQ-1 story 01 — near matches: requirements in the account whose key contains this key, or the reverse ("Forklift" and "Forklift licence"), shown BEFORE saving so near-duplicates are not created by accident. An exact key match is the duplicate rule (E-REQ-003), not a near match. Archived ones are included, flagged. At most 5. Read-only. TWO PASSES: the first marks every row with a 0/1 `match` computed from the row alone (arithmetic, no conditional); the second keeps the rows whose OWN `match` is 1, because a conditional that reads a variable updated earlier in the same iteration silently loses its writes (CLAUDE.md).
function "req/similar" {
  input {
    int account_id filters=min:1
    text key? filters=trim
    int exclude_id?
  }

  stack {
    db.query requirement {
      where = $db.requirement.account_id == $input.account_id
      return = {type: "list"}
      output = ["id", "name", "name_key", "is_active"]
    } as $rows

    var $marked {
      value = []
    }

    var $a {
      value = 0
    }

    var $b {
      value = 0
    }

    var $m {
      value = 0
    }

    var $other {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        var.update $a {
          value = ($r.name_key|contains:$input.key)|to_int
        }

        var.update $b {
          value = ($input.key|contains:$r.name_key)|to_int
        }

        var.update $other {
          value = (($r.name_key != $input.key) && ($r.id != $input.exclude_id))|to_int
        }

        var.update $m {
          value = ((($a + $b) > 0)|to_int) * $other
        }

        array.push $marked {
          value = {id: $r.id, name: $r.name, is_active: $r.is_active, match: $m}
        }
      }
    }

    var $out {
      value = []
    }

    foreach ($marked) {
      each as $c {
        conditional {
          if ($c.match == 1) {
            array.push $out {
              value = {id: $c.id, name: $c.name, is_active: $c.is_active}
            }
          }
        }
      }
    }

    var $limited {
      value = $out|slice:0:5
    }
  }

  response = {matches: $limited}
}
