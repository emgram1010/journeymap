// v1.0 — Formats a completed workflow_execution as JSON, Markdown, or clipboard text.
// Called by the Orchestrator agent after a run completes.
// US-WE-21
tool export_workflow_output {
  instructions = """
      Use this tool to export a completed workflow run in one of three formats.
    
      Inputs:
      - execution_id: ID of the workflow_execution record.
      - format: 'json' | 'markdown' | 'clipboard'
        json      = full artifact with all stage outputs
        markdown  = human-readable report with H2 stage headers
        clipboard = final stage primary_output only (the deliverable)
    
      Response: { format, content, execution_id, subject_label }
      The 'content' field is the formatted string ready for display or download.
    """

  input {
    int execution_id filters=min:1
    enum format {
      values = ["json", "markdown", "clipboard"]
    }
  
    int journey_map_id?
    int conversation_id_log?
    text turn_id?
  }

  stack {
    db.get workflow_execution {
      field_name = "id"
      field_value = $input.execution_id
    } as $exec
  
    var $content {
      value = ""
    }
  
    // ── JSON format — return the full execution record as JSON string ──
    conditional {
      if ($input.format == "json") {
        var.update $content {
          value = "Run ID: " ~ ($exec.id|to_text) ~ " | Subject: " ~ ($exec.subject_label ?? "—") ~ " | Status: " ~ $exec.status ~ " | Stages: " ~ ($exec.completed_stages|count|to_text) ~ " | stage_outputs (raw): use get_workflow_state to fetch the full JSON artifact."
        }
      }
    }
  
    // ── Markdown format — one heading per completed stage ──
    conditional {
      if ($input.format == "markdown") {
        var $md {
          value = "# Workflow Run: " ~ ($exec.subject_label ?? "Untitled") ~ "\n\n**Status:** " ~ $exec.status ~ "\n\n---\n\n"
        }
      
        conditional {
          if ($exec.completed_stages != null) {
            foreach ($exec.completed_stages) {
              each as $sk {
                var $stage_out {
                  value = $exec.stage_outputs|get:$sk
                }
              
                var.update $md {
                  value = $md|concat:"## Stage: ":""
                }
              
                var.update $md {
                  value = $md|concat:$sk:""
                }
              
                var.update $md {
                  value = $md|concat:"\n\n":""
                }
              
                var.update $md {
                  value = $md
                    |concat:$stage_out.output ?? "_No output recorded._":""
                }
              
                var.update $md {
                  value = $md|concat:"\n\n---\n\n":""
                }
              }
            }
          }
        }
      
        var.update $content {
          value = $md
        }
      }
    }
  
    // ── Clipboard — final stage output only ──
    conditional {
      if ($input.format == "clipboard") {
        var $last_output {
          value = ""
        }
      
        conditional {
          if ($exec.completed_stages != null) {
            foreach ($exec.completed_stages) {
              each as $sk {
                var $cs_out {
                  value = $exec.stage_outputs|get:$sk
                }
              
                var.update $last_output {
                  value = ($cs_out.output ?? "")
                }
              }
            }
          }
        }
      
        var.update $content {
          value = $last_output
        }
      }
    }
  
    // Tool trace logging
    conditional {
      if ($input.conversation_id_log != null && $input.turn_id != null) {
        db.add agent_tool_log {
          data = {
            conversation  : $input.conversation_id_log
            journey_map   : $input.journey_map_id
            turn_id       : $input.turn_id
            tool_name     : "export_workflow_output"
            tool_category : "workflow"
            input_summary : "execution: " ~ ($input.execution_id|to_text) ~ " format: " ~ $input.format
            output_summary: "exported " ~ $input.format
          }
        } as $exp_log
      }
    }
  }

  response = {
    execution_id : $input.execution_id
    subject_label: $exec.subject_label
    format       : $input.format
    content      : $content
  }
}