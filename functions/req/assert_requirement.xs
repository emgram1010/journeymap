// REQ-1 story 01 — the guard: this requirement exists AND belongs to the caller's account, else "Requirement not found. (E-REQ-006)". Another account's requirement answers exactly like one that does not exist, so ids cannot be probed. Returns the row. Used by every endpoint that takes a requirement id.
function "req/assert_requirement" {
  input {
    int account_id filters=min:1
    int requirement_id filters=min:1
  }

  stack {
    db.query requirement {
      where = $db.requirement.id == $input.requirement_id && $db.requirement.account_id == $input.account_id
      return = {type: "single"}
    } as $row

    var $found_id {
      value = $row|get:"id":0
    }

    precondition ($found_id != 0) {
      error_type = "notfound"
      error = "Requirement not found. (E-REQ-006)"
    }
  }

  response = {requirement: $row}
}
