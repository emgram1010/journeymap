// COP-1 — is the AI tool gate refusing yet, or only reporting? "report" = log what it WOULD refuse and refuse nothing; "enforce" = refuse. Four switches: outside assistants (the tool address) and in-app agents, each for read tools and write tools, so each can go first on its own. Changing a value here and pushing this one function changes every tool at once; changing it back is the rollback.
function "usr/tool_gate_mode" {
  input {
  }

  stack {
    var $modes {
      value = {outside_read: "enforce", outside_write: "enforce", inapp_read: "report", inapp_write: "report"}
    }
  }

  response = $modes
}
