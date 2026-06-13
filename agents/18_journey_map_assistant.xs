// The Journey Map Assistant agent guides PM interviews, answers freeform questions,
// and uses generic tools to read, write, and reshape any journey map — without hardcoded
// schema knowledge. The orchestrator injects live map state and mode rules into the
// system prompt before each call.
// v2: added update_actor_cell_fields, update_actor_identity, update_journey_settings tools
agent "Journey Map Assistant" {
  canonical = "pBv2E_k_"
  llm = {
    type         : "anthropic"
    system_prompt: "temp"
    max_steps    : 20
    messages     : "{{ $args.messages|json_encode() }}"
    api_key      : "{{ $env.ANTHROPIC_KEY }}"
    model        : "claude-sonnet-4-5"
    temperature  : 0.3
    reasoning    : false
    baseURL      : ""
    headers      : ""
  }

  tools = [
    {name: "get_map_state"}
    {name: "get_slice"}
    {name: "get_gaps"}
    {name: "search_cells"}
    {name: "update_cell"}
    {name: "batch_update"}
    {name: "update_actor_cell_fields"}
    {name: "update_actor_identity"}
    {name: "update_journey_settings"}
    {name: "set_cell_status"}
    {name: "batch_set_status"}
    {name: "mutate_structure"}
    {name: "scaffold_structure"}
    {name: "infer_stage_metrics"}
    {name: "list_scenarios"}
    {name: "clone_scenario"}
    {name: "compare_scenarios"}
    {name: "link_map"}
    {name: "update_stage_contract"}
  ]
}