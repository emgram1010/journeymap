// Compare Analyst chat endpoint.
// Accepts two map IDs + a user message, injects dual scorecard context,
// calls the Journey Compare Analyst agent, and returns the reply.
query "journey_architecture/{journey_architecture_id}/compare/message" verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id? filters=min:1
    int map_a_id?                filters=min:1
    int map_b_id?                filters=min:1
    int conversation_id?
    text content?                filters=trim
  }

  stack {
    precondition ($input.content != null && $input.content != "") {
      error_type = "inputerror"
      error = "Message content is required"
    }

    precondition ($input.map_a_id != null && $input.map_b_id != null && $input.map_a_id != $input.map_b_id) {
      error_type = "inputerror"
      error = "Two different map IDs are required"
    }

    db.get journey_architecture {
      field_name = "id"
      field_value = $input.journey_architecture_id
    } as $arch

    precondition ($arch != null && $arch.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Architecture not found or access denied"
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.map_a_id
    } as $map_a

    precondition ($map_a != null) {
      error_type = "notfound"
      error = "Scenario A not found"
    }

    db.get journey_map {
      field_name = "id"
      field_value = $input.map_b_id
    } as $map_b

    precondition ($map_b != null) {
      error_type = "notfound"
      error = "Scenario B not found"
    }

    // ── Map A: fetch ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.map_a_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages_a

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.map_a_id && $db.journey_lens.actor_type == "metrics"
      return = {type: "single"}
    } as $metrics_lens_a

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.map_a_id && $db.journey_lens.template_key == "financial-v1"
      return = {type: "single"}
    } as $financial_lens_a

    // ── Map A: accumulators ──
    var $stage_rows_a {
      value = []
    }

    var $health_sum_a {
      value = 0
    }

    var $health_count_a {
      value = 0
    }

    var $fin_rar_a {
      value = 0
    }

    var $fin_cts_a {
      value = 0
    }

    var $fin_asy_a {
      value = 0
    }

    var $fin_uop_a {
      value = 0
    }

    var $map_health_a {
      value = null
    }

    var $map_hl_a {
      value = null
    }

    // ── Map A: foreach stages (scorecard pattern) ──
    foreach ($stages_a) {
      each as $stage {
        var $stage_health_a {
          value = null
        }

        var $hl_a {
          value = null
        }

        var $mc_a {
          value = null
        }

        var $af_a {
          value = null
        }

        var $sh_a {
          value = null
        }

        var $fc_a {
          value = null
        }

        var $faf_a {
          value = null
        }

        var $cts_a {
          value = null
        }

        var $rar_a {
          value = null
        }

        var $asy_a {
          value = null
        }

        var $uop_a {
          value = null
        }

        conditional {
          if ($metrics_lens_a != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.map_a_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $metrics_lens_a.id
              return = {type: "single"}
            } as $mc_a

            conditional {
              if ($mc_a != null && $mc_a.actor_fields != null) {
                var.update $af_a {
                  value = $mc_a.actor_fields
                }

                var.update $sh_a {
                  value = $af_a|get:"stage_health"
                }

                conditional {
                  if ($sh_a != null) {
                    var.update $stage_health_a {
                      value = $sh_a|to_text|to_decimal
                    }
                  }
                }
              }
            }
          }
        }

        conditional {
          if ($stage_health_a != null && $stage_health_a >= 8) {
            var.update $hl_a {
              value = "healthy"
            }
          }
        }

        conditional {
          if ($stage_health_a != null && $stage_health_a >= 5 && $stage_health_a < 8) {
            var.update $hl_a {
              value = "at_risk"
            }
          }
        }

        conditional {
          if ($stage_health_a != null && $stage_health_a < 5) {
            var.update $hl_a {
              value = "critical"
            }
          }
        }

        conditional {
          if ($stage_health_a != null) {
            var.update $health_sum_a {
              value = $health_sum_a + $stage_health_a
            }

            var.update $health_count_a {
              value = $health_count_a + 1
            }
          }
        }

        conditional {
          if ($financial_lens_a != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.map_a_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $financial_lens_a.id
              return = {type: "single"}
            } as $fc_a

            conditional {
              if ($fc_a != null && $fc_a.actor_fields != null) {
                var.update $faf_a {
                  value = $fc_a.actor_fields
                }

                var.update $cts_a {
                  value = $faf_a|get:"cost_to_serve"
                }

                var.update $rar_a {
                  value = $faf_a|get:"revenue_at_risk"
                }

                var.update $asy_a {
                  value = $faf_a|get:"automation_savings"
                }

                var.update $uop_a {
                  value = $faf_a|get:"upsell_opportunity"
                }

                conditional {
                  if ($cts_a != null) {
                    var.update $fin_cts_a {
                      value = $fin_cts_a + ($cts_a|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($rar_a != null) {
                    var.update $fin_rar_a {
                      value = $fin_rar_a + ($rar_a|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($asy_a != null) {
                    var.update $fin_asy_a {
                      value = $fin_asy_a + ($asy_a|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($uop_a != null) {
                    var.update $fin_uop_a {
                      value = $fin_uop_a + ($uop_a|to_text|to_decimal)
                    }
                  }
                }
              }
            }
          }
        }

        var.update $stage_rows_a {
          value = $stage_rows_a|push:{stage_key: $stage.key, stage_label: $stage.label, health: $stage_health_a, health_label: $hl_a}
        }
      }
    }

    conditional {
      if ($health_count_a > 0) {
        var.update $map_health_a {
          value = ($health_sum_a / $health_count_a)|round:1
        }
      }
    }

    conditional {
      if ($map_health_a != null && $map_health_a >= 8) {
        var.update $map_hl_a {
          value = "healthy"
        }
      }
    }

    conditional {
      if ($map_health_a != null && $map_health_a >= 5 && $map_health_a < 8) {
        var.update $map_hl_a {
          value = "at_risk"
        }
      }
    }

    conditional {
      if ($map_health_a != null && $map_health_a < 5) {
        var.update $map_hl_a {
          value = "critical"
        }
      }
    }

    // ── Map B: fetch ──
    db.query journey_stage {
      where = $db.journey_stage.journey_map == $input.map_b_id
      sort = {display_order: "asc"}
      return = {type: "list"}
    } as $stages_b

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.map_b_id && $db.journey_lens.actor_type == "metrics"
      return = {type: "single"}
    } as $metrics_lens_b

    db.query journey_lens {
      where = $db.journey_lens.journey_map == $input.map_b_id && $db.journey_lens.template_key == "financial-v1"
      return = {type: "single"}
    } as $financial_lens_b

    // ── Map B: accumulators ──
    var $stage_rows_b {
      value = []
    }

    var $health_sum_b {
      value = 0
    }

    var $health_count_b {
      value = 0
    }

    var $fin_rar_b {
      value = 0
    }

    var $fin_cts_b {
      value = 0
    }

    var $fin_asy_b {
      value = 0
    }

    var $fin_uop_b {
      value = 0
    }

    var $map_health_b {
      value = null
    }

    var $map_hl_b {
      value = null
    }

    // ── Map B: foreach stages (scorecard pattern) ──
    foreach ($stages_b) {
      each as $stage {
        var $stage_health_b {
          value = null
        }

        var $hl_b {
          value = null
        }

        var $mc_b {
          value = null
        }

        var $af_b {
          value = null
        }

        var $sh_b {
          value = null
        }

        var $fc_b {
          value = null
        }

        var $faf_b {
          value = null
        }

        var $cts_b {
          value = null
        }

        var $rar_b {
          value = null
        }

        var $asy_b {
          value = null
        }

        var $uop_b {
          value = null
        }

        conditional {
          if ($metrics_lens_b != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.map_b_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $metrics_lens_b.id
              return = {type: "single"}
            } as $mc_b

            conditional {
              if ($mc_b != null && $mc_b.actor_fields != null) {
                var.update $af_b {
                  value = $mc_b.actor_fields
                }

                var.update $sh_b {
                  value = $af_b|get:"stage_health"
                }

                conditional {
                  if ($sh_b != null) {
                    var.update $stage_health_b {
                      value = $sh_b|to_text|to_decimal
                    }
                  }
                }
              }
            }
          }
        }

        conditional {
          if ($stage_health_b != null && $stage_health_b >= 8) {
            var.update $hl_b {
              value = "healthy"
            }
          }
        }

        conditional {
          if ($stage_health_b != null && $stage_health_b >= 5 && $stage_health_b < 8) {
            var.update $hl_b {
              value = "at_risk"
            }
          }
        }

        conditional {
          if ($stage_health_b != null && $stage_health_b < 5) {
            var.update $hl_b {
              value = "critical"
            }
          }
        }

        conditional {
          if ($stage_health_b != null) {
            var.update $health_sum_b {
              value = $health_sum_b + $stage_health_b
            }

            var.update $health_count_b {
              value = $health_count_b + 1
            }
          }
        }

        conditional {
          if ($financial_lens_b != null) {
            db.query journey_cell {
              where = $db.journey_cell.journey_map == $input.map_b_id && $db.journey_cell.stage == $stage.id && $db.journey_cell.lens == $financial_lens_b.id
              return = {type: "single"}
            } as $fc_b

            conditional {
              if ($fc_b != null && $fc_b.actor_fields != null) {
                var.update $faf_b {
                  value = $fc_b.actor_fields
                }

                var.update $cts_b {
                  value = $faf_b|get:"cost_to_serve"
                }

                var.update $rar_b {
                  value = $faf_b|get:"revenue_at_risk"
                }

                var.update $asy_b {
                  value = $faf_b|get:"automation_savings"
                }

                var.update $uop_b {
                  value = $faf_b|get:"upsell_opportunity"
                }

                conditional {
                  if ($cts_b != null) {
                    var.update $fin_cts_b {
                      value = $fin_cts_b + ($cts_b|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($rar_b != null) {
                    var.update $fin_rar_b {
                      value = $fin_rar_b + ($rar_b|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($asy_b != null) {
                    var.update $fin_asy_b {
                      value = $fin_asy_b + ($asy_b|to_text|to_decimal)
                    }
                  }
                }

                conditional {
                  if ($uop_b != null) {
                    var.update $fin_uop_b {
                      value = $fin_uop_b + ($uop_b|to_text|to_decimal)
                    }
                  }
                }
              }
            }
          }
        }

        var.update $stage_rows_b {
          value = $stage_rows_b|push:{stage_key: $stage.key, stage_label: $stage.label, health: $stage_health_b, health_label: $hl_b}
        }
      }
    }

    conditional {
      if ($health_count_b > 0) {
        var.update $map_health_b {
          value = ($health_sum_b / $health_count_b)|round:1
        }
      }
    }

    conditional {
      if ($map_health_b != null && $map_health_b >= 8) {
        var.update $map_hl_b {
          value = "healthy"
        }
      }
    }

    conditional {
      if ($map_health_b != null && $map_health_b >= 5 && $map_health_b < 8) {
        var.update $map_hl_b {
          value = "at_risk"
        }
      }
    }

    conditional {
      if ($map_health_b != null && $map_health_b < 5) {
        var.update $map_hl_b {
          value = "critical"
        }
      }
    }

    // ── Build context ──
    var $ctx {
      value = "## Scenario A: "
    }

    var.update $ctx {
      value = $ctx|concat:$map_a.title:""
    }

    var.update $ctx {
      value = $ctx|concat:" (map_id: " ~ ($input.map_a_id|to_text) ~ ")\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Journey Health: " ~ ($map_health_a|to_text) ~ " (" ~ $map_hl_a ~ ")\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Financial: RAR $" ~ ($fin_rar_a|to_text) ~ " | CTS $" ~ ($fin_cts_a|to_text) ~ " | ASY $" ~ ($fin_asy_a|to_text) ~ " | UOP $" ~ ($fin_uop_a|to_text) ~ "\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Stages:\n":""
    }

    foreach ($stage_rows_a) {
      each as $row {
        var $rh {
          value = "null"
        }

        var $rhl {
          value = "no data"
        }

        conditional {
          if ($row.health != null) {
            var.update $rh {
              value = $row.health|to_text
            }
          }
        }

        conditional {
          if ($row.health_label != null) {
            var.update $rhl {
              value = $row.health_label
            }
          }
        }

        var.update $ctx {
          value = $ctx|concat:"- " ~ $row.stage_label ~ " (" ~ $row.stage_key ~ "): " ~ $rh ~ " (" ~ $rhl ~ ")\n":""
        }
      }
    }

    var.update $ctx {
      value = $ctx|concat:"\n## Scenario B: " ~ $map_b.title ~ " (map_id: " ~ ($input.map_b_id|to_text) ~ ")\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Journey Health: " ~ ($map_health_b|to_text) ~ " (" ~ $map_hl_b ~ ")\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Financial: RAR $" ~ ($fin_rar_b|to_text) ~ " | CTS $" ~ ($fin_cts_b|to_text) ~ " | ASY $" ~ ($fin_asy_b|to_text) ~ " | UOP $" ~ ($fin_uop_b|to_text) ~ "\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"Stages:\n":""
    }

    foreach ($stage_rows_b) {
      each as $row {
        var $rh {
          value = "null"
        }

        var $rhl {
          value = "no data"
        }

        conditional {
          if ($row.health != null) {
            var.update $rh {
              value = $row.health|to_text
            }
          }
        }

        conditional {
          if ($row.health_label != null) {
            var.update $rhl {
              value = $row.health_label
            }
          }
        }

        var.update $ctx {
          value = $ctx|concat:"- " ~ $row.stage_label ~ " (" ~ $row.stage_key ~ "): " ~ $rh ~ " (" ~ $rhl ~ ")\n":""
        }
      }
    }

    // ── Delta summary ──
    var $b_wins {
      value = 0
    }

    var $a_wins {
      value = 0
    }

    var $delta_rows {
      value = ""
    }

    foreach ($stage_rows_a) {
      each as $ra {
        var $rb_health {
          value = null
        }

        foreach ($stage_rows_b) {
          each as $rb {
            conditional {
              if ($rb.stage_key == $ra.stage_key) {
                var.update $rb_health {
                  value = $rb.health
                }
              }
            }
          }
        }

        var $d_str {
          value = "—"
        }

        var $w_str {
          value = "tied"
        }

        var $ra_str {
          value = "null"
        }

        var $rb_str {
          value = "null"
        }

        conditional {
          if ($ra.health != null) {
            var.update $ra_str {
              value = $ra.health|to_text
            }
          }
        }

        conditional {
          if ($rb_health != null) {
            var.update $rb_str {
              value = $rb_health|to_text
            }
          }
        }

        conditional {
          if ($ra.health != null && $rb_health != null) {
            var $dv {
              value = ($rb_health - $ra.health)|round:1
            }

            conditional {
              if ($dv > 0) {
                var.update $d_str {
                  value = "+" ~ ($dv|to_text)
                }

                var.update $w_str {
                  value = $map_b.title
                }

                var.update $b_wins {
                  value = $b_wins + 1
                }
              }
            }

            conditional {
              if ($dv < 0) {
                var $abs_dv {
                  value = (0 - $dv)|round:1
                }

                var.update $d_str {
                  value = "-" ~ ($abs_dv|to_text)
                }

                var.update $w_str {
                  value = $map_a.title
                }

                var.update $a_wins {
                  value = $a_wins + 1
                }
              }
            }
          }
        }

        var.update $delta_rows {
          value = $delta_rows ~ "| " ~ $ra.stage_label ~ " | " ~ $ra_str ~ " | " ~ $rb_str ~ " | " ~ $d_str ~ " | " ~ $w_str ~ " |\n"
        }
      }
    }

    var.update $ctx {
      value = $ctx|concat:"\n## Delta Summary\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"| Stage | " ~ $map_a.title ~ " | " ~ $map_b.title ~ " | Delta | Winner |\n":""
    }

    var.update $ctx {
      value = $ctx|concat:"|---|---|---|---|---|\n":""
    }

    var.update $ctx {
      value = $ctx|concat:$delta_rows:""
    }

    var.update $ctx {
      value = $ctx|concat:"Overall: " ~ $map_b.title ~ " wins " ~ ($b_wins|to_text) ~ " stages, " ~ $map_a.title ~ " wins " ~ ($a_wins|to_text) ~ " stages\n":""
    }

    // ── Conversation ──
    var $conv {
      value = null
    }

    var $reply {
      value = ""
    }

    var $thinking {
      value = null
    }

    var $agent_run {
      value = null
    }

    var $agent_err {
      value = null
    }

    conditional {
      if ($input.conversation_id != null) {
        db.get agent_conversation {
          field_name = "id"
          field_value = $input.conversation_id
        } as $req_conv

        conditional {
          if ($req_conv != null) {
            var.update $conv {
              value = $req_conv
            }
          }
        }
      }
    }

    conditional {
      if ($conv == null) {
        db.add agent_conversation {
          data = {
            created_at              : "now"
            journey_map             : $input.map_a_id
            map_b_id                : $input.map_b_id
            journey_architecture_id : $input.journey_architecture_id
            owner_user              : $auth.id
            title                   : "Compare: " ~ $map_a.title ~ " vs " ~ $map_b.title
            mode                    : "compare"
            last_message_at         : "now"
          }
        } as $new_conv

        var.update $conv {
          value = $new_conv
        }
      }
    }

    db.query agent_message {
      where = $db.agent_message.conversation == $conv.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $history

    db.add agent_message {
      data = {
        created_at  : "now"
        conversation: $conv.id
        role        : "user"
        mode        : "compare"
        content     : []|push:({}|set:"type":"text"|set:"text":$input.content)
      }
    } as $user_msg

    var $turn_id {
      value = "turn_" ~ ($conv.id|to_text) ~ "_" ~ ($user_msg.id|to_text)
    }

    var.update $ctx {
      value = $ctx|concat:"\n## Tool Logging\n- map_a_id: " ~ ($input.map_a_id|to_text) ~ "\n- map_b_id: " ~ ($input.map_b_id|to_text) ~ "\n- conversation_id: " ~ ($conv.id|to_text) ~ "\n- turn_id: " ~ $turn_id ~ "\n":""
    }

    // ── Build messages array ──
    var $agent_msgs {
      value = []
    }

    array.push $agent_msgs {
      value = {role: "system", content: $ctx}
    }

    var $max_hist {
      value = 20
    }

    var $hist_start {
      value = 0
    }

    var $hist_total {
      value = $history|count
    }

    conditional {
      if ($hist_total > $max_hist) {
        var.update $hist_start {
          value = $hist_total - $max_hist
        }
      }
    }

    var $hidx {
      value = 0
    }

    foreach ($history) {
      each as $hm {
        conditional {
          if ($hidx >= $hist_start) {
            var $hm_text {
              value = ""
            }

            conditional {
              if ($hm.content != null) {
                api.lambda {
                  code = """
                    const content = $var.hm.content;
                    if (Array.isArray(content)) {
                      return content.map(c => c.text || '').join('\n');
                    }
                    return typeof content === 'string' ? content : JSON.stringify(content);
                  """
                  timeout = 5
                } as $extracted_text

                var.update $hm_text {
                  value = $extracted_text
                }
              }
            }

            conditional {
              if ($hm_text != "") {
                array.push $agent_msgs {
                  value = {role: $hm.role, content: $hm_text}
                }
              }
            }
          }
        }

        var.update $hidx {
          value = $hidx + 1
        }
      }
    }

    array.push $agent_msgs {
      value = {role: "user", content: $input.content}
    }

    // ── Call Journey Compare Analyst ──
    try_catch {
      try {
        group {
          stack {
            ai.agent.run "Journey Compare Analyst" {
              args = {}|set:"messages":$agent_msgs
              allow_tool_execution = true
            } as $agent_run_inner

            var.update $agent_run {
              value = $agent_run_inner
            }
          }
        }
      }

      catch {
        var.update $agent_err {
          value = $error.message
        }
      }
    }

    conditional {
      if ($agent_run != null) {
        var $ar {
          value = $agent_run|get:"result"
        }

        conditional {
          if ($ar != null && $ar != "") {
            var.update $reply {
              value = $ar
            }
          }
        }

        var.update $thinking {
          value = $agent_run|get:"thinking"
        }
      }
    }

    conditional {
      if ($agent_err != null && $reply == "") {
        var.update $reply {
          value = $agent_err
        }
      }
    }

    conditional {
      if ($reply != "") {
        db.add agent_message {
          data = {
            created_at  : "now"
            conversation: $conv.id
            role        : "assistant"
            mode        : "compare"
            content     : []|push:({}|set:"type":"text"|set:"text":$reply)
            thinking    : $thinking
          }
        } as $saved_reply
      }
    }

    db.patch agent_conversation {
      field_name = "id"
      field_value = $conv.id
      data = {last_message_at: "now"}
    } as $conv_record

    db.query agent_message {
      where = $db.agent_message.conversation == $conv.id
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $all_msgs
  }

  response = {
    reply          : $reply
    conversation_id: $conv.id
    conversation   : $conv_record
    messages       : $all_msgs
    thinking       : $thinking
  }
  guid = "lI0xXgogr9Rtheu52z24NZKTWHo"
}
