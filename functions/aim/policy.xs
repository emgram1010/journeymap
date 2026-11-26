// AIM-1 story 08 — THE one list of what an AI member may ever do, by tool name. Each tool is in exactly one class: read, draft_map, draft_plan, own_work (the four an admin may grant), or ceiling (no AI member may ever call it, whatever its scope: publishing, deleting, creating a business, spending money). A tool that is not in this list has no class and is refused for an AI member by default, so a new tool is closed until someone adds it here. Changing this list is a code change with a review, never a setting. No approve, permission, token, password or settings tool exists at all; if one is ever added it goes under ceiling.
function "aim/policy" {
  input {
    text tool? filters=trim
  }

  stack {
    var $classes {
      value = {
        list_maps             : "read"
        search_maps           : "read"
        get_map               : "read"
        get_map_state         : "read"
        get_slice             : "read"
        get_gaps              : "read"
        get_stage_detail      : "read"
        search_cells          : "read"
        list_scenarios        : "read"
        compare_scenarios     : "read"
        calculate_leakage     : "read"
        get_how_i_work        : "read"
        check_publish_ready   : "read"
        plan_list             : "read"
        plan_get              : "read"
        plan_live_days        : "read"
        list_tags             : "read"
        list_business_jobs    : "read"
        get_job_variance      : "read"
        get_map_learnings     : "read"
        list_my_tasks         : "read"
        create_journey_map    : "draft_map"
        scaffold_map          : "draft_map"
        scaffold_structure    : "draft_map"
        build_journey_map     : "draft_map"
        fill_cells            : "draft_map"
        update_cell           : "draft_map"
        batch_update          : "draft_map"
        update_stage_contract : "draft_map"
        update_actor_identity : "draft_map"
        update_journey_settings: "draft_map"
        clone_scenario        : "draft_map"
        link_map              : "draft_map"
        tag_map               : "draft_map"
        untag_map             : "draft_map"
        plan_create           : "draft_plan"
        plan_accept_map       : "draft_plan"
        plan_add_job          : "draft_plan"
        plan_add_on_demand_job: "draft_plan"
        plan_add_person       : "draft_plan"
        plan_start_day        : "draft_plan"
        plan_schedule_step    : "draft_plan"
        plan_schedule_card    : "draft_plan"
        plan_unschedule_step  : "draft_plan"
        plan_set_start_time   : "draft_plan"
        plan_set_time_window  : "draft_plan"
        plan_repeat           : "draft_plan"
        record_my_task_event  : "own_work"
        publish_map           : "ceiling"
        create_workspace      : "ceiling"
        mutate_structure      : "ceiling"
        request_step_up       : "ceiling"
      }
    }

    var $tool {
      value = $input.tool ?? ""
    }

    var $klass {
      value = ($classes|get:$tool:null) ?? ""
    }
  }

  response = {tool: $tool, klass: $klass, grantable: ["read", "draft_map", "draft_plan", "own_work"], classes: $classes}
}
