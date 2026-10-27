// PUB-1 (US-PUB-1-04) — Recomputes a stored version's hash from its own
// stored snapshot and compares it to the hash recorded at publish time.
//
// This is the whole point of content_hash: versions are immutable by
// rule (no update or delete endpoint exists), and this is how that rule
// is checked rather than merely asserted. A mismatch means the row was
// changed outside the publish path — a direct database edit, a restore
// gone wrong, or tampering — and is an engineer-level problem, not
// something a user can fix (E-PUB-003).
function "pub/verify_version" {
  description = "Recomputes a version's content hash from its stored snapshot. Returns valid=false on any mismatch."

  input {
    int journey_map_version_id filters=min:1
  }

  stack {
    db.get journey_map_version {
      field_name = "id"
      field_value = $input.journey_map_version_id
    } as $version

    precondition ($version != null) {
      error_type = "notfound"
      error = "Version not found"
    }

    function.run "pub/canonical_hash" {
      input = {snapshot: $version.snapshot}
    } as $recomputed

    var $stored_hash {
      value = $version.content_hash ?? ""
    }

    var $valid {
      value = ($stored_hash != "" && $stored_hash == $recomputed.hash)
    }

    // RATE-1 (US-RATE-1-05) — canonical_hash already re-serialises with
    // the snapshot's OWN schema_version, so v1 and v2 both verify above.
    // For v2 the rate card also lives in stage_rate: its row count must
    // equal snapshot.rates. A mismatch is E-RATE-003 (reported by
    // ops/audit_rates), kept separate from `valid` because the hash —
    // the frozen definition itself — is still intact.
    var $schema_version {
      value = $version.snapshot.schema_version ?? 1
    }

    var $snapshot_rates {
      value = 0
    }

    var $rate_rows {
      value = 0
    }

    var $rates_matched {
      value = 0
    }

    conditional {
      if ($schema_version >= 2) {
        var.update $snapshot_rates {
          value = ($version.snapshot.rates ?? [])|count
        }

        db.query stage_rate {
          where = $db.stage_rate.journey_map_version_id == $input.journey_map_version_id
          return = {type: "list"}
        } as $rate_list

        var.update $rate_rows {
          value = $rate_list|count
        }

        // Review finding #2 — compare CONTENT, not only the count: EST-1
        // reads minutes from stage_rate, so a hand-patched value would
        // change estimates while the hash (over the snapshot) still
        // verified. Each stored row becomes "minutes::source" under its
        // "stage::quantity::method" key; every snapshot rate must find
        // its exact twin. Minutes compared as fixed-2-decimal text.
        var $stored_by_key {
          value = {}
        }

        foreach ($rate_list) {
          each as $stored_rate {
            var $stored_key {
              value = $stored_rate.stage_key ~ "::" ~ $stored_rate.quantity_key ~ "::" ~ $stored_rate.method_key
            }

            var $stored_val {
              value = ($stored_rate.minutes_per_unit|number_format:2:".":"") ~ "::" ~ $stored_rate.source
            }

            var.update $stored_by_key {
              value = $stored_by_key|set:$stored_key:$stored_val
            }
          }
        }

        var $snapshot_rate_list {
          value = $version.snapshot.rates ?? []
        }

        foreach ($snapshot_rate_list) {
          each as $snap_rate {
            var $snap_key {
              value = ($snap_rate.stage_key ?? "") ~ "::" ~ ($snap_rate.quantity_key ?? "") ~ "::" ~ ($snap_rate.method_key ?? "")
            }

            var $snap_val {
              value = (($snap_rate.minutes_per_unit ?? 0)|number_format:2:".":"") ~ "::" ~ ($snap_rate.source ?? "")
            }

            var $stored_match {
              value = $stored_by_key|get:$snap_key:null
            }

            var.update $rates_matched {
              value = $rates_matched + (($stored_match == $snap_val)|to_int)
            }
          }
        }
      }
    }

    var $rates_ok {
      value = ($rate_rows == $snapshot_rates && $rates_matched == $snapshot_rates)
    }
  }

  response = {
    valid          : $valid
    journey_map_id : $version.journey_map_id
    version_no     : $version.version_no
    stored_hash    : $stored_hash
    recomputed_hash: $recomputed.hash
    schema_version : $schema_version
    rates_ok       : $rates_ok
    snapshot_rates : $snapshot_rates
    rate_rows      : $rate_rows
    rates_matched  : $rates_matched
  }
}
