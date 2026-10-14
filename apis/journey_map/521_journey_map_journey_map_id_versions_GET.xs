// PUB-1 (US-PUB-1-05) — Version history for one map, newest first.
//
// Deliberately omits each version's `snapshot` payload: a map with many
// versions would otherwise return megabytes of frozen definition for what
// is usually just a list. Fetch one version (api 522) to get its snapshot.
//
// `latest_hash` is here for stale detection (deferred per D-39): comparing
// it against a hash of the live definition is how "this map has changed
// since it was last published" will be answered.
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
          }
        }
      }
    }
  }

  response = {
    journey_map_id: $input.journey_map_id
    count         : ($versions|count)
    latest_hash   : $latest_hash
    versions      : $versions
  }
}
