// REPEAT-1 story 07 — Plain words for what a repeat left out, one sentence each, so an AI (or anyone reading an answer) never has to guess what a reason code means. Pure: no database. Input is the `left_out` list a repeat returns: [{kind: person|map|job|line|slot, name, reason}]. A reason it does not know gets a neutral sentence, never the raw code. Every branch is a ternary on the current item, hoisted into a variable first (a ternary inside an object literal drops the keys after it, CLAUDE.md).
function "repeat/describe_left_out" {
  input {
    json left_out
  }

  stack {
    var $lines {
      value = []
    }

    var $noun {
      value = ""
    }

    var $why {
      value = ""
    }

    var $label {
      value = ""
    }

    var $line {
      value = ""
    }

    foreach ($input.left_out) {
      each as $o {
        var.update $noun {
          value = (($o.kind == "person") ? "Person" : (($o.kind == "map") ? "Map" : (($o.kind == "job") ? "Job" : (($o.kind == "line") ? "Item" : "Scheduled slot"))))
        }

        var.update $why {
          value = "it could not be repeated"
        }

        var.update $why {
          value = (($o.reason == "inactive") ? "they are switched off on the plan, so they were not added" : $why)
        }

        var.update $why {
          value = (($o.reason == "login_off") ? "they can no longer sign in, so they were not added" : $why)
        }

        var.update $why {
          value = (($o.reason == "map_unavailable") ? "its map was archived, deleted or is not this account's" : $why)
        }

        var.update $why {
          value = (($o.reason == "item_inactive") ? "that item has been switched off in Settings" : $why)
        }

        var.update $why {
          value = (($o.reason == "item_not_in_version") ? "that item is not on the map as it is published now" : $why)
        }

        var.update $why {
          value = (($o.reason == "step_gone") ? "that step is not in the map as it is published now" : $why)
        }

        var.update $why {
          value = (($o.reason == "job_not_repeated") ? "its job was not repeated" : $why)
        }

        var.update $why {
          value = (($o.reason == "switched_off") ? "they are switched off on the plan, so they would not be added" : $why)
        }

        var.update $why {
          value = (($o.reason == "outside_order") ? "it came from a customer order, so it is a one-off" : $why)
        }

        var.update $why {
          value = (($o.reason == "exception_child") ? "it was created by an exception on another job" : $why)
        }

        var.update $why {
          value = (($o.reason == "cancelled") ? "it was cancelled" : $why)
        }

        var.update $why {
          value = (($o.reason == "no_published_version") ? "its map has no published version" : $why)
        }

        var.update $why {
          value = (($o.reason == "map_not_accepted") ? "its map is no longer one this plan uses" : $why)
        }

        var.update $why {
          value = (($o.reason == "left_out") ? "it was left out on request" : $why)
        }

        var.update $label {
          value = (($o.name != "") ? $o.name : "(no name)")
        }

        var.update $line {
          value = $noun ~ " " ~ $label ~ ": " ~ $why ~ "."
        }

        array.push $lines {
          value = $line
        }
      }
    }
  }

  response = {lines: $lines, count: ($lines|count)}
}
