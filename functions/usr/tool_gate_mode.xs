// COP-1 — is the AI tool gate refusing yet, or only reporting? "report" = log what it WOULD refuse and refuse nothing; "enforce" = refuse. One switch for read tools and one for write tools, so reads can go first. Changing a value here and pushing this one function changes every tool at once; changing it back is the rollback.
function "usr/tool_gate_mode" {
  input {
  }

  stack {
    var $modes {
      value = {read: "report", write: "report"}
    }
  }

  response = $modes
}
