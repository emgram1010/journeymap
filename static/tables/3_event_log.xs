// Stores logs of user activities and events within the application.
// ── RES-3 Lifecycle classification ───────────────────────────────────────
// Growth class    : HIGH (append-only; every user action + RES-8 telemetry).
// Dominant window : last 7d for ops dashboards; last 30d for audit.
// Old rows read?  : Rarely — compliance/forensics only.
// Retention       : 90 days (configurable via retention_policy table).
// Prune cadence   : daily 03:00 UTC (task: prune_event_log).
// ── OBS-1 (phase-4) — Observability columns ───────────────────────────────
// Added additively so this table can also serve as the system "heartbeat"
// and error log for every phase-4 epic. Existing rows/writers are
// unaffected: all new columns are nullable and default to null.
// System events (heartbeat, daily audit) carry no account_id/user_id.
// See product/stories/phase-4/EPIC-OBS-1-observability-and-heartbeat.md.
table event_log {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    // Reference to the user who performed the action.
    int user_id? {
      table = "user"
    }

    // Reference to the company associated with the user event.
    int account_id? {
      table = "account"
    }

    // A description of the action performed by the user (e.g., 'login', 'created_invoice', 'updated_profile').
    text action? filters=trim

    // Additional data related to the event, such as resource IDs, old/new values, or other contextual information.
    json metadata?

    // ── OBS-1: observability fields ──────────────────────────────────────
    // How serious this event is. Drives Health page coloring.
    enum severity? {
      values = ["info", "warn", "error"]
    }

    // Whether the step succeeded, was correctly refused, or broke unexpectedly.
    // success = the heartbeat. rejected = validation/permission/readiness
    // correctly stopped it. failure = something broke that shouldn't have.
    enum outcome? {
      values = ["success", "rejected", "failure"]
    }

    // The epic/feature this event belongs to (e.g. "OBS-1", "PUB-1").
    text feature? filters=trim

    // The specific step within the feature (e.g. "publish_version").
    text step? filters=trim

    // What kind of thing this event is about (e.g. "work_item", "journey_map").
    text entity_type? filters=trim

    // The id of the entity this event is about, if any.
    int entity_id?

    // Generated once per user action and threaded through every event it
    // produces. Shown to the user as "Reference" on errors.
    text correlation_id? filters=trim

    // Catalog error code, e.g. "E-PUB-001". Null for success events.
    text error_code? filters=trim

    // Plain-English description of what happened. No stack traces, no
    // secrets — see the error catalog for the authoritative user-facing text.
    text message? filters=trim

    // How long the step took, in milliseconds.
    int duration_ms?
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
    {
      type : "btree"
      field: [
        {name: "account_id", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {
      type : "btree"
      field: [
        {name: "outcome", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {
      type : "btree"
      field: [
        {name: "feature", op: "asc"}
        {name: "created_at", op: "desc"}
      ]
    }
    {type: "btree", field: [{name: "correlation_id", op: "asc"}]}
    {
      type : "btree"
      field: [
        {name: "entity_type", op: "asc"}
        {name: "entity_id", op: "asc"}
      ]
    }
  ]

  tags = ["xano:quick-start"]
}