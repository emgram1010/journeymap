// DEMAND-1 story 01 (decision D-11) — the publication|v3 canonical text and its hash for a list of ALREADY-FROZEN snapshot items. live/build_publication builds the same line from the live plan; this one builds it from stored items only, so a day that grew by an add-only version can be hashed without reading the plan again. Line shape and escape order are copied from live/build_publication (backslash, pipe, CR, newline). An old item with no window or no manual start gives empty fields. Twin: webapp/protype-2/src/liveAppend.ts::canonicalItems. Read-only.
function "live/canonical_items" {
  input {
    json items?
  }

  stack {
    var $no_window {
      value = {start_date: "", start_time: "", end_date: "", end_time: "", note: ""}
    }

    var $canonical {
      value = "publication|v3\n"
    }

    var $w {
      value = null
    }

    var $sd {
      value = ""
    }

    var $st {
      value = ""
    }

    var $ed {
      value = ""
    }

    var $et {
      value = ""
    }

    var $esc_note {
      value = ""
    }

    var $esc_ref {
      value = ""
    }

    var $esc_title {
      value = ""
    }

    var $wt_joined {
      value = ""
    }

    var $sov {
      value = ""
    }

    var $line {
      value = ""
    }

    var $count {
      value = 0
    }

    foreach ($input.items) {
      each as $i {
        var.update $count {
          value = $count + 1
        }

        var.update $w {
          value = ($i|get:"time_window":null) ?? $no_window
        }

        var.update $sd {
          value = ($w|get:"start_date":"") ?? ""
        }

        var.update $st {
          value = ($w|get:"start_time":"") ?? ""
        }

        var.update $ed {
          value = ($w|get:"end_date":"") ?? ""
        }

        var.update $et {
          value = ($w|get:"end_time":"") ?? ""
        }

        var.update $esc_note {
          value = (($w|get:"note":"") ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $esc_ref {
          value = ($i.item_ref ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $esc_title {
          value = ($i.title ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $wt_joined {
          value = $i.work_task_ids|join:","
        }

        var.update $sov {
          value = ($i|get:"start_override":"") ?? ""
        }

        var.update $line {
          value = "item|" ~ $esc_ref ~ "|" ~ ($i.seq|to_text) ~ "|" ~ ($i.scheduled_minutes|to_text) ~ "|" ~ ($i.assignee_agent_id|to_text) ~ "|" ~ $esc_title ~ "|" ~ $wt_joined ~ "|" ~ $sd ~ "|" ~ $st ~ "|" ~ $ed ~ "|" ~ $et ~ "|" ~ $esc_note ~ "|" ~ $sov ~ "\n"
        }

        var.update $canonical {
          value = $canonical ~ $line
        }
      }
    }

    var $hash {
      value = $canonical|sha256
    }
  }

  response = {canonical: $canonical, snapshot_hash: $hash, item_count: $count}
}
