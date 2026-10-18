// PUB-1 (US-PUB-1-05) — Version history for one map, newest first.
//
// Deliberately omits each version's `snapshot` payload: a map with many
// versions would otherwise return megabytes of frozen definition for what
// is usually just a list. Fetch one version (api 522) to get its snapshot.
//
// GAP-FIX W6 (2026-10-17) — STALE DETECTION IS NOW ANSWERED HERE, not
// merely possible. `latest_hash` was left for this purpose and deferred
// (D-39); the deferral is what made "you have edited this map since you
// published it" invisible, which is the dangerous half of W6: a planner
// tidies up a step's wording, assumes it is live, and every plan keeps
// running the old frozen copy. That behaviour is CORRECT — freezing is
// the point — but silent, so it reads as a bug.
//
// HOW: the live definition is rebuilt through the SAME two functions
// the publish endpoint itself uses (`pub/build_map_snapshot` then
// `pub/canonical_hash`) and its hash compared with the stored one. Not
// a second implementation — the identical pair — because a stale check
// with its own idea of the canonical form would eventually disagree
// with the publisher and be confidently wrong either way (CLAUDE.md:
// put the shared rule in one function). Verified live on maps 205 (v3)
// and 206 (v1): an untouched map re-hashes byte-identically.
//
// `has_unpublished_changes` is FALSE for a map that has never been
// published — there is nothing to have drifted from, and
// `latest_version_no: null` already says "never published".
query "journey_map/{journey_map_id}/versions" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "You don't have access to this map. (E-PUB-004)"
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      sort = {version_no: "desc"}
      return = {type: "list"}
    } as $version_rows

    var $versions {
      value = []
    }

    foreach ($version_rows) {
      each as $row {
        array.push $versions {
          value = {
            id                    : $row.id
            version_no            : $row.version_no
            content_hash          : $row.content_hash
            published_at          : $row.published_at
            published_by          : $row.published_by
            automation_snapshot_id: $row.automation_snapshot_id
            stage_count           : ($row.snapshot.stages|count)
          }
        }
      }
    }

    var $latest_hash {
      value = null
    }

    var $latest_version_no {
      value = null
    }

    var $latest_published_at {
      value = null
    }

    var $highest_version {
      value = 0
    }

    foreach ($version_rows) {
      each as $row2 {
        conditional {
          if ($row2.version_no > $highest_version) {
            var.update $highest_version {
              value = $row2.version_no
            }

            var.update $latest_hash {
              value = $row2.content_hash
            }

            var.update $latest_version_no {
              value = $row2.version_no
            }

            var.update $latest_published_at {
              value = $row2.published_at
            }
          }
        }
      }
    }

    function.run "pub/build_map_snapshot" {
      input = {journey_map_id: $input.journey_map_id}
    } as $live

    function.run "pub/canonical_hash" {
      input = {snapshot: $live.snapshot}
    } as $live_hash

    var $has_unpublished_changes {
      value = ($latest_hash != null && $latest_hash != $live_hash.hash)
    }
  }

  response = {
    journey_map_id         : $input.journey_map_id
    count                  : ($versions|count)
    latest_hash            : $latest_hash
    latest_version_no      : $latest_version_no
    latest_published_at    : $latest_published_at
    live_hash              : $live_hash.hash
    has_unpublished_changes: $has_unpublished_changes
    versions               : $versions
  }
}
