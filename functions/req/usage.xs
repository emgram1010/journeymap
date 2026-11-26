// REQ-1 story 01 — how many places use a requirement: steps of a map (draft needs), people who hold it, and published versions that froze it. Read-only. Counted by query (return type count), never by loading rows. A requirement used anywhere cannot be deleted (E-REQ-004): archive it instead. The same three numbers are shown on the list. Tenancy is the caller's job (req/assert_requirement); the counts are scoped by the requirement id, which belongs to one account.
function "req/usage" {
  input {
    int requirement_id filters=min:1
  }

  stack {
    db.query journey_cell_requirement {
      where = $db.journey_cell_requirement.requirement_id == $input.requirement_id
      return = {type: "count"}
    } as $steps

    db.query agent_profile_requirement {
      where = $db.agent_profile_requirement.requirement_id == $input.requirement_id
      return = {type: "count"}
    } as $people

    db.query journey_map_version_requirement {
      where = $db.journey_map_version_requirement.requirement_id == $input.requirement_id
      return = {type: "count"}
    } as $versions
  }

  response = {steps: $steps, people: $people, versions: $versions, total: ($steps + $people + $versions)}
}
