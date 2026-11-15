// COP-1 story 04 (2026-11-15) — the AI audit trail: one row for every AI tool call, from any
// caller, saying WHO made it. Written by journey/tool_gate before the tool does anything, so a
// refused call is recorded too. Append-only: rows are never edited or deleted (it is the record
// of what an AI did, listed in src/ops/historyTables.ts).
//
// What it holds: who (user + account + how they were identified), which tool, which map or
// business it named, and the gate's verdict. It deliberately holds NO tool input, no ticket and
// no token — a call's content can contain customer text or secrets.
//
// `verdict` is the gate's decision at the START of the call: "allowed", "would_refuse" (report
// mode, the tool ran anyway) or "refused". It is not the tool's own success or failure.
//
// GOV-1: S1 primary key; S2 created_at only (append-only); S3 references declared and indexed.
table tool_call_log {
  auth = false

  schema {
    int id

    timestamp created_at?=now {
      visibility = "private"
    }

    int user_id? {
      table = "user"
      description = "Who made the call. 0 = could not be identified (refused)."
    }

    int account_id? {
      description = "That person's account. 0 = unknown."
    }

    text tool? filters=trim {
      description = "The tool's name, e.g. update_cell."
    }

    enum kind? {
      values = ["read", "write"]
      description = "Whether the tool only reads or can change things."
    }

    int journey_map_id? {
      description = "The map the call named. 0 = none."
    }

    int journey_architecture_id? {
      description = "The business (architecture) the call named. 0 = none."
    }

    enum context? {
      values = ["outside", "inapp"]
      description = "outside = the tool address (an outside assistant); inapp = an agent inside Emgram."
    }

    enum via? {
      values = ["ticket", "token", "none"]
      description = "How the caller was identified."
    }

    enum verdict? {
      values = ["allowed", "would_refuse", "refused"]
      description = "The gate's decision at the start of the call."
    }

    text code? filters=trim {
      description = "Refusal code when the verdict is not 'allowed' (E-SEC-020, E-COP-001, E-COP-002)."
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "user_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}, {name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "journey_map_id", op: "asc"}]}
  ]
}
