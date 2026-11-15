// COP-2 stories 01/05 — "what level does this action type have in this business, for this amount?" The ONE lookup. Unknown type → wait. Locked type → its default, whatever is stored. No stored row → the default (decision D-8). Money types: at "wait" with a limit above 0, an amount UNDER the limit runs at "tell"; at or over, or with no amount, it waits; a limit of 0 always waits. Never throws.
function "copilot/action_level" {
  input {
    int journey_architecture_id?
    text action_type? filters=trim
    int amount?
    bool has_amount?
  }

  stack {
    function.run "copilot/action_types" {
      input = {}
    } as $cat

    // A variable key with a missing entry gives null (and ignores any default, CLAUDE.md), so the
    // null IS the "unknown type" signal. Prefixing is not needed: an empty key is refused first.
    var $type_key {
      value = $input.action_type
    }

    var $t {
      value = null
    }

    conditional {
      if ($type_key != "") {
        var.update $t {
          value = $cat.types|get:$type_key:null
        }
      }
    }

    var $known {
      value = ($t != null)
    }

    var $default_level {
      value = "wait"
    }

    var $locked {
      value = false
    }

    var $person_only {
      value = false
    }

    var $has_limit {
      value = false
    }

    var $reversible {
      value = false
    }

    var $touches {
      value = "unknown"
    }

    conditional {
      if ($known == true) {
        var.update $default_level {
          value = $t|get:"default_level":"wait"
        }

        var.update $locked {
          value = $t|get:"locked":false
        }

        var.update $person_only {
          value = $t|get:"person_only":false
        }

        var.update $has_limit {
          value = $t|get:"has_limit":false
        }

        var.update $reversible {
          value = $t|get:"reversible":false
        }

        var.update $touches {
          value = $t|get:"touches":"unknown"
        }
      }
    }

    // COP-2 review fix: maps outside any business (architecture 0) ALWAYS use the defaults. A
    // stored row for 0 would be shared by every account (the unique key has no account in it), so
    // it is never read here and POST copilot/level_set refuses to write one (E-COP-039).
    var $lookup_arch {
      value = $input.journey_architecture_id
    }

    db.query copilot_action_level {
      where = $lookup_arch != 0 && $db.copilot_action_level.journey_architecture_id == $lookup_arch && $db.copilot_action_level.action_type == $type_key
      return = {type: "single"}
    } as $row

    var $stored_level {
      value = $row|get:"level":""
    }

    var $limit_amount {
      value = $row|get:"limit_amount":0
    }

    var $level {
      value = $default_level
    }

    conditional {
      if ($known == true && $locked == false && $stored_level != "") {
        var.update $level {
          value = $stored_level
        }
      }
    }

    var $effective {
      value = $level
    }

    var $under_limit {
      value = ($has_limit == true && $level == "wait" && $limit_amount > 0 && $input.has_amount == true && $input.amount >= 0 && $input.amount < $limit_amount)
    }

    conditional {
      if ($under_limit == true) {
        var.update $effective {
          value = "tell"
        }
      }
    }

    var $reason {
      value = "This kind of action waits for you."
    }

    conditional {
      if ($known == false) {
        var.update $reason {
          value = "This kind of action is not in the list, so it waits for you."
        }
      }

      elseif ($has_limit == true && $level == "wait" && $under_limit == false && $limit_amount > 0) {
        var.update $reason {
          value = "The amount is at or over your limit, so it waits for you."
        }
      }

      elseif ($touches != "internal") {
        var.update $reason {
          value = "It reaches a customer, a booking or money, so it waits for you."
        }
      }
    }
  }

  response = {
    action_type    : $type_key
    known          : $known
    level          : $level
    effective_level: $effective
    locked         : $locked
    person_only    : $person_only
    has_limit      : $has_limit
    limit_amount   : $limit_amount
    reversible     : $reversible
    touches        : $touches
    reason         : $reason
  }
}
