// REQ-1 story 05 — tamper evidence for ONE version's frozen needs: re-read its journey_map_version_requirement rows, rebuild the canonical string and hash with the SAME rule (req/needs_hash), and compare with the hash stored when it was published. Read-only. ok is true when they match, or when the version has no needs and no hash row (nothing to prove). It is NOT ok when rows exist with no hash row, when a hash row exists with no rows, when the counts differ, or when the hashes differ. Returns the reason, never throws, so the nightly audit can log every mismatch and carry on.
function "req/verify_needs" {
  input {
    int journey_map_version_id filters=min:1
  }

  stack {
    db.query journey_map_version_requirement {
      where = $db.journey_map_version_requirement.journey_map_version_id == $input.journey_map_version_id
      return = {type: "list"}
    } as $rows

    db.query journey_map_version_needs_hash {
      where = $db.journey_map_version_needs_hash.journey_map_version_id == $input.journey_map_version_id
      return = {type: "single"}
    } as $stored

    var $stored_hash {
      value = $stored|get:"needs_hash":""
    }

    var $stored_count {
      value = $stored|get:"need_count":0
    }

    var $stored_id {
      value = $stored|get:"id":0
    }

    function.run "req/needs_hash" {
      input = {rows: $rows}
    } as $h

    var $row_count {
      value = $rows|count
    }

    var $nothing {
      value = ($row_count == 0) && ($stored_id == 0)
    }

    var $same {
      value = ($stored_id != 0) && ($row_count == $stored_count) && ($h.hash == $stored_hash)
    }

    var $reason {
      value = (($nothing == true || $same == true) ? "" : (($row_count > 0 && $stored_id == 0) ? "rows_without_hash" : (($row_count == 0) ? "hash_without_rows" : (($row_count != $stored_count) ? "count_differs" : "hash_differs"))))
    }
  }

  response = {ok: ($reason == ""), reason: $reason, rows: $row_count, stored_count: $stored_count, computed_hash: $h.hash, stored_hash: $stored_hash}
}
