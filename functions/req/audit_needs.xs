// REQ-1 story 05 — the nightly check on every version's frozen needs: for each version that has frozen needs or a needs hash, re-verify it (req/verify_needs) and log a FAILURE event (E-REQ-036, error) for each mismatch, named by version, so Health shows it. Called from the nightly integrity task, beside the snapshot and rate audits. Read-only apart from the events. Never throws: a version that cannot be checked is simply listed. Returns how many versions were checked and the mismatches.
function "req/audit_needs" {
  input {
    int dummy?
  }

  stack {
    db.query journey_map_version_requirement {
      return = {type: "list"}
      output = ["journey_map_version_id"]
    } as $row_versions

    db.query journey_map_version_needs_hash {
      return = {type: "list"}
      output = ["journey_map_version_id"]
    } as $hash_versions

    var $seen {
      value = {}
    }

    var $to_check {
      value = []
    }

    var $k {
      value = ""
    }

    var $t {
      value = ""
    }

    foreach ($row_versions) {
      each as $rv {
        var.update $t {
          value = $rv.journey_map_version_id|to_text
        }

        var.update $k {
          value = "v:" ~ $t
        }

        var.update $seen {
          value = $seen|set:$k:1
        }
      }
    }

    foreach ($hash_versions) {
      each as $hv {
        var.update $t {
          value = $hv.journey_map_version_id|to_text
        }

        var.update $k {
          value = "v:" ~ $t
        }

        var.update $seen {
          value = $seen|set:$k:1
        }
      }
    }

    var $ids {
      value = $seen|keys
    }

    var $findings {
      value = []
    }

    var $vid_text {
      value = ""
    }

    var $vid {
      value = 0
    }

    foreach ($ids) {
      each as $key {
        var.update $vid_text {
          value = "/^v:/"|regex_replace:"":$key
        }

        var.update $vid {
          value = $vid_text|to_int
        }

        function.run "req/verify_needs" {
          input = {journey_map_version_id: $vid}
        } as $v

        array.push $findings {
          value = {version_id: $vid, ok: $v.ok, reason: $v.reason}
        }
      }
    }

    var $bad {
      value = []
    }

    foreach ($findings) {
      each as $f {
        conditional {
          if ($f.ok == false) {
            array.push $bad {
              value = $f
            }

            function.run "ops/log_event" {
              input = {
                feature       : "REQ-1"
                step          : "needs_integrity_mismatch"
                outcome       : "failure"
                severity      : "error"
                error_code    : "E-REQ-036"
                message       : "A published version's frozen needs do not match the hash stored when it was published."
                user_id       : 0
                account_id    : 0
                entity_type   : "journey_map_version"
                entity_id     : $f.version_id
                correlation_id: ""
                metadata      : {reason: $f.reason}
              }
            } as $_logged
          }
        }
      }
    }
  }

  response = {versions_checked: ($findings|count), mismatch_count: ($bad|count), mismatches: $bad}
}
