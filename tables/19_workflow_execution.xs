// v1.0 — Stores a single execution run of a journey map workflow.
// Enables resumable sessions, multi-run history, and execution state persistence.
// ── Automation Bridge fields (v2) ────────────────────────────────────────
// Null for standard AI orchestrator runs. Populated when a run is spawned
// by an external automation tool (n8n/Make) following a journey_link branch.
table workflow_execution {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }
  
    // Timestamp of the last state change (stage advance, pause, complete).
    timestamp updated_at?
  
    // The journey map being executed.
    int journey_map? {
      table = "journey_map"
    }
  
    // The conversation thread this execution is tied to.
    int conversation? {
      table = "agent_conversation"
    }
  
    // The user who initiated this execution run.
    int owner_user? {
      table = "user"
    }
  
    // Domain subject of this run (e.g., "Jeff", "Acme Corp", "Ticket #42").
    // Kept short — the full subject context is in subject_context.
    text subject_label? filters=trim
  
    // Free-form context block about the subject — injected into agent context at each stage.
    text subject_context?
  
    // Execution mode: step = user confirms each stage; auto = runs all stages unattended.
    enum execution_mode? {
      values = ["step", "auto"]
    }
  
    // Overall status of the run.
    enum status? {
      values = ["pending", "running", "paused", "completed", "failed", "cancelled"]
    }
  
    // The stage key currently being executed (null = not yet started).
    text current_stage_key? filters=trim
  
    // Zero-based index of the current stage in the sorted execution order.
    int current_stage_index?
  
    // Total number of stages eligible for execution (internal actor present).
    int total_stages?
  
    // Structured map of completed stage outputs keyed by stage_key.
    // { "s1": { "output": "...", "completed_at": "..." }, ... }
    json stage_outputs?
  
    // Snapshot of the validation report at execution start.
    json validation_snapshot?
  
    // Timestamp when execution actually started (first stage run).
    timestamp started_at?
  
    // Timestamp when the run reached completed/failed/cancelled status.
    timestamp finished_at?
  
    // Short human-readable summary of why the run failed or was cancelled.
    text failure_reason? filters=trim
  
    // The parent execution that triggered this linked-map run.
    // Null for top-level (main map) runs.
    int parent_execution_id? {
      table = "workflow_execution"
    }
  
    // The map that originated the branch (main map for exception/sub/anti runs).
    int originating_map_id? {
      table = "journey_map"
    }
  
    // The specific cell in the originating map where the journey_link was followed.
    int originating_cell_id? {
      table = "journey_cell"
    }
  
    // The type of journey_link that spawned this run.
    // Null for main-map runs and AI orchestrator sessions.
    enum execution_link_type? {
      values = ["exception", "anti_journey", "sub_journey"]
    }
  
    // Free-form context snapshot from n8n when an unknown exception fires.
    // Shape: { stage_key, exception_type, external_context: { ... } }
    json exception_context?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {type: "btree", field: [{name: "journey_map", op: "asc"}]}
    {type: "btree", field: [{name: "conversation", op: "asc"}]}
    {type: "btree", field: [{name: "owner_user", op: "asc"}]}
    {type: "btree", field: [{name: "status", op: "asc"}]}
    {
      type : "btree"
      field: [
        {name: "journey_map", op: "asc"}
        {name: "status", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {
      type : "btree"
      field: [{name: "parent_execution_id", op: "asc"}]
    }
    {
      type : "btree"
      field: [
        {name: "owner_user", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
  ]

  tags = ["xano:quick-start"]
}