// RATE-1 (US-RATE-1-05, FT-RATE-1-06/07) — Version integrity audit.
// Read-only apart from the one event it logs.
//
// Walks EVERY journey_map_version and runs pub/verify_version on it:
//   - hash mismatch      → E-PUB-003 (the frozen definition was edited)
//   - stage_rate rows ≠ snapshot.rates (v2 only) → E-RATE-003 (a rate
//     row was deleted or added outside publish)
//
// A separate function, not more checks inside ops/audit_integrity: that
// one walks the live DEFINITION tables, and PLN-8 showed this workspace
// rejects a single audit function once it grows past a certain size.
// Same split as ops/audit_execution.
//
// Uses verify_version itself — not a second copy of its rules — so the
// audit can never disagree with the check the version page shows.
// One function.run per version: fine for a nightly job, not for a
// request path.
//
// Logs one event per finding type: `RATE-1.rate_integrity_mismatch`
// (E-RATE-003) and `PUB-1.version_integrity` (E-PUB-003, including a
// version verify_version could not run on), or one `RATE-1.version_audit`
// success when clean. Formerly: when any E-RATE-003 finding exists it logs ONE `rate_integrity_mismatch`
// failure event (feature RATE-1), which the Health page lists with an
// owner and a fix hint from the error catalog.
function "ops/audit_rates" {
  input {
  }

  stack {
    db.query journey_map_version {
      sort = {id: "asc"}
      return = {type: "list"}
    } as $versions

    var $findings {
      value = []
    }

    var $hash_mismatch_count {
      value = 0
    }

    var $rate_mismatch_count {
      value = 0
    }

    var $v2_count {
      value = 0
    }

    var $unverifiable_count {
      value = 0
    }

    // Founder decision D-R1 (2026-10-25): a hash mismatch on a version
    // whose map is ARCHIVED is still reported in the response but raises
    // no Health event. Map 200's three hand-built JOB-1 fixture versions
    // were archived for exactly this reason. Rate mismatches still alert
    // regardless: stage_rate is what estimates read.
    var $archived_hash_mismatch_count {
      value = 0
    }

    db.query journey_map {
      where = $db.journey_map.status == "archived"
      return = {type: "list"}
    } as $archived_maps

    var $archived_map_ids {
      value = {}
    }

    foreach ($archived_maps) {
      each as $archived_map {
        var $archived_map_key {
          value = $archived_map.id|to_text
        }

        var.update $archived_map_ids {
          value = $archived_map_ids|set:$archived_map_key:true
        }
      }
    }

    // One bad row must not abort the whole nightly check (review #3):
    // version 5 used to crash verify_version and take the loop with it.
    foreach ($versions) {
      each as $version_row {
        try_catch {
          try {
            function.run "pub/verify_version" {
              input = {journey_map_version_id: $version_row.id}
            } as $check

            // Counters fold the test into arithmetic (bool|to_int) instead
            // of branching (CLAUDE.md foreach/conditional trap).
            var $vm_key {
              value = $version_row.journey_map_id|to_text
            }

            var $vm_archived_hit {
              value = $archived_map_ids|get:$vm_key:null
            }

            var $vm_archived {
              value = ($vm_archived_hit != null)
            }

            var.update $hash_mismatch_count {
              value = $hash_mismatch_count + (($check.valid == false && $vm_archived == false)|to_int)
            }

            var.update $archived_hash_mismatch_count {
              value = $archived_hash_mismatch_count + (($check.valid == false && $vm_archived == true)|to_int)
            }

            var.update $rate_mismatch_count {
              value = $rate_mismatch_count + (($check.rates_ok == false)|to_int)
            }

            var.update $v2_count {
              value = $v2_count + (($check.schema_version >= 2)|to_int)
            }

            conditional {
              if ($check.valid == false) {
                array.push $findings {
                  value = {check: "content_hash", error_code: "E-PUB-003", journey_map_version_id: $version_row.id, journey_map_id: $check.journey_map_id, version_no: $check.version_no, archived_map: $vm_archived, detail: "stored hash does not match the stored snapshot"}
                }
              }
            }

            conditional {
              if ($check.rates_ok == false) {
                array.push $findings {
                  value = {check: "stage_rate", error_code: "E-RATE-003", journey_map_version_id: $version_row.id, journey_map_id: $check.journey_map_id, version_no: $check.version_no, detail: "snapshot has " ~ ($check.snapshot_rates|to_text) ~ " rates; stage_rate has " ~ ($check.rate_rows|to_text) ~ " rows, " ~ ($check.rates_matched|to_text) ~ " matching"}
                }
              }
            }
          }

          catch {
            var.update $unverifiable_count {
              value = $unverifiable_count + 1
            }

            array.push $findings {
              value = {check: "verify_error", error_code: "E-PUB-003", journey_map_version_id: $version_row.id, journey_map_id: $version_row.journey_map_id, version_no: $version_row.version_no, detail: "verify_version could not run on this version"}
            }
          }
        }
      }
    }

    var $hash_problem_count {
      value = $hash_mismatch_count + $unverifiable_count
    }

    // Every finding type reaches the Health page as its own event; a clean
    // run logs a success so "the audit ran" is visible too (OBS-1).
    conditional {
      if ($rate_mismatch_count > 0) {
        var $rate_message {
          value = ($rate_mismatch_count|to_text) ~ " published version(s) have rate rows that don't match their snapshot."
        }

        function.run "ops/log_event" {
          input = {
            feature   : "RATE-1"
            step      : "rate_integrity_mismatch"
            outcome   : "failure"
            severity  : "warn"
            error_code: "E-RATE-003"
            message   : $rate_message
            metadata  : {rate_mismatch_count: $rate_mismatch_count}
          }
        } as $_rate_logged
      }
    }

    conditional {
      if ($hash_problem_count > 0) {
        var $hash_message {
          value = ($hash_problem_count|to_text) ~ " published version(s) no longer match their stored hash."
        }

        function.run "ops/log_event" {
          input = {
            feature   : "PUB-1"
            step      : "version_integrity"
            outcome   : "failure"
            severity  : "warn"
            error_code: "E-PUB-003"
            message   : $hash_message
            metadata  : {hash_mismatch_count: $hash_mismatch_count, unverifiable_count: $unverifiable_count}
          }
        } as $_hash_logged
      }
    }

    var $finding_count {
      value = $hash_problem_count + $rate_mismatch_count
    }

    conditional {
      if ($finding_count == 0) {
        function.run "ops/log_event" {
          input = {
            feature : "RATE-1"
            step    : "version_audit"
            outcome : "success"
            severity: "info"
            message : "Every published version verified, rates included."
            metadata: {versions_checked: ($versions|count), v2_versions: $v2_count}
          }
        } as $_clean_logged
      }
    }
  }

  response = {
    finding_count      : $finding_count
    hash_mismatch_count: $hash_mismatch_count
    unverifiable_count : $unverifiable_count
    archived_hash_mismatch_count: $archived_hash_mismatch_count
    rate_mismatch_count: $rate_mismatch_count
    versions_checked   : ($versions|count)
    v2_versions        : $v2_count
    findings           : $findings
  }
}
