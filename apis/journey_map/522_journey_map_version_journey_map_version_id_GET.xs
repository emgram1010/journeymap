// PUB-1 (US-PUB-1-05) — One frozen version, including its snapshot.
//
// There is deliberately no PATCH or DELETE sibling to this endpoint:
// versions are immutable (US-PUB-1-04), and the way that rule is enforced
// is that no write path exists at all. Direct attempts return 404.
//
// `verified` recomputes the hash from the stored snapshot on every read,
// so a tampered row is visible the moment anyone looks at it rather than
// only when a daily audit runs.
query "journey_map_version/{journey_map_version_id}" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_version_id? filters=min:1
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

    // Access is decided by the map the version belongs to — a version has
    // no owner of its own.
    db.get journey_map {
      field_name = "id"
      field_value = $version.journey_map_id
    } as $journey_map

    precondition ($journey_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }

    precondition ($journey_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "You don't have access to this map. (E-PUB-004)"
    }

    function.run "pub/verify_version" {
      input = {journey_map_version_id: $input.journey_map_version_id}
    } as $verification
  }

  response = {
    id                    : $version.id
    journey_map_id        : $version.journey_map_id
    version_no            : $version.version_no
    snapshot              : $version.snapshot
    content_hash          : $version.content_hash
    readiness_report      : $version.readiness_report
    automation_snapshot_id: $version.automation_snapshot_id
    published_by          : $version.published_by
    published_at          : $version.published_at
    verified              : $verification.valid
  }
}
