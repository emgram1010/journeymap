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
  }

  response = {
    valid          : $valid
    journey_map_id : $version.journey_map_id
    version_no     : $version.version_no
    stored_hash    : $stored_hash
    recomputed_hash: $recomputed.hash
  }
}
