// REPEAT-1 stories 01 + 06 — THE one rule for a repeated plan's name: the source's name with any earlier "(YYYY-MM-DD)" (and its " 2" counter) taken off, then " (<start date>)", then " 2", " 3"… up to 9 until the account has no plan of that name. repeat/build_plan (the preview and the copy) and repeat/list_periods (several periods, one name each) both call it. Reads only. `free` is false when all nine tries were taken (the caller still gets the last candidate, and the copy is refused by the unique name index).
function "repeat/free_name" {
  input {
    int account_id
    text source_name filters=trim
    text start_date filters=trim
  }

  stack {
    var $base_full {
      value = "/ [(][0-9]{4}-[0-9]{2}-[0-9]{2}[)]( [0-9])?$/"|regex_replace:"":$input.source_name
    }

    var $base {
      value = $base_full|substr:0:64
    }

    var $suffix {
      value = " (" ~ $input.start_date ~ ")"
    }

    var $try {
      value = 1
    }

    var $try_text {
      value = "1"
    }

    var $name_free {
      value = false
    }

    var $candidate {
      value = $base ~ $suffix
    }

    while ($name_free == false && $try <= 9) {
      each {
        var.update $try_text {
          value = $try|to_text
        }

        var.update $candidate {
          value = (($try == 1) ? ($base ~ $suffix) : ($base ~ $suffix ~ " " ~ $try_text))
        }

        db.query planner_workspace {
          where = $db.planner_workspace.account_id == $input.account_id && $db.planner_workspace.name == $candidate
          return = {type: "count"}
        } as $clash

        var.update $name_free {
          value = ($clash == 0)
        }

        var.update $try {
          value = $try + 1
        }
      }
    }
  }

  response = {name: $candidate, free: $name_free}
}
