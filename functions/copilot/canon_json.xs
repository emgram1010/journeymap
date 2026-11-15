// COP-2 — a JSON value in the database's own normal form, as text, so two values can be compared for "the same content". A json column re-orders keys on the way back (found live), so a stored value and a fresh one never json_encode the same. This writes the value to copilot_json_canon, reads it back, encodes it, and deletes the row.
function "copilot/canon_json" {
  input {
    json value?
  }

  stack {
    var $v {
      value = $input.value ?? {}
    }

    db.add copilot_json_canon {
      data = {body: $v}
    } as $row

    db.query copilot_json_canon {
      where = $db.copilot_json_canon.id == $row.id
      return = {type: "single"}
    } as $back

    var $text {
      value = ($back.body ?? {})|json_encode
    }

    db.del copilot_json_canon {
      field_name = "id"
      field_value = $row.id
    }
  }

  response = {text: $text}
}
