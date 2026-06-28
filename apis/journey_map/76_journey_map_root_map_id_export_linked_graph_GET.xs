// US-EXP-1-01 — Architecture-aware graph walker for the linked-bundle exporter.
// Given a root_map_id, walks journey_link edges + journey_map.parent_map_id +
// journey_lens.agent_map_id and returns every reachable map id plus the edges
// connecting them. Bounded BFS with cycle detection and depth cap. Owner-scoped.
// Hydration of stages/lenses/cells is deferred — the frontend calls load_bundle
// per visited_map_ids[] entry so this endpoint stays predictable in shape/size.
query "journey_map/{root_map_id}/export/linked_graph" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int root_map_id? filters=min:1
    int max_depth?=5 filters=min:1|max:10
    bool include_agent_manuals?=true
    bool include_children?=true
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.root_map_id
    } as $root_map
  
    precondition ($root_map != null) {
      error_type = "notfound"
      error = "Journey map not found"
    }
  
    precondition ($root_map.owner_user == $auth.id) {
      error_type = "accessdenied"
      error = "Access denied"
    }
  
    var $architecture_id {
      value = $root_map.journey_architecture
    }
  
    db.query journey_map {
      where = $db.journey_map.journey_architecture == $architecture_id
      return = {type: "list"}
    } as $arch_maps
  
    db.query journey_link {
      where = $db.journey_link.journey_architecture == $architecture_id
      return = {type: "list"}
    } as $arch_links
  
    var $visited {
      value = [$input.root_map_id]
    }
  
    var $frontier {
      value = [$input.root_map_id]
    }
  
    var $links_out {
      value = []
    }
  
    var $walk_warnings {
      value = []
    }
  
    var $depth {
      value = 0
    }
  
    var $walk_status {
      value = "running"
    }
  
    while ($walk_status == "running") {
      each {
        var $next_frontier {
          value = []
        }
      
        foreach ($frontier) {
          each as $cur_id {
            // 1) Outbound journey_link edges (same architecture only)
            foreach ($arch_links) {
              each as $lk {
                conditional {
                  if ($lk.source_map == $cur_id) {
                    var.update $links_out {
                      value = $links_out|push:$lk
                    }
                  
                    conditional {
                      if (!($visited|contains:$lk.target_map)) {
                        var.update $visited {
                          value = $visited|push:$lk.target_map
                        }
                      
                        var.update $next_frontier {
                          value = $next_frontier|push:$lk.target_map
                        }
                      }
                    }
                  }
                }
              }
            }
          
            // 2) Children via parent_map_id
            conditional {
              if ($input.include_children) {
                foreach ($arch_maps) {
                  each as $am {
                    conditional {
                      if ($am.parent_map_id == $cur_id && !($visited|contains:$am.id)) {
                        var.update $visited {
                          value = $visited|push:$am.id
                        }
                      
                        var.update $next_frontier {
                          value = $next_frontier|push:$am.id
                        }
                      
                        var.update $links_out {
                          value = $links_out
                            |push:```
                              {
                                source_map          : $cur_id
                                target_map          : $am.id
                                link_type           : "parent_child"
                                label               : "child"
                                journey_architecture: $architecture_id
                              }
                              ```
                        }
                      }
                    }
                  }
                }
              }
            }
          
            // 3) Agent-manual targets via journey_lens.agent_map_id (may cross-arch)
            conditional {
              if ($input.include_agent_manuals) {
                db.query journey_lens {
                  where = $db.journey_lens.journey_map == $cur_id && $db.journey_lens.agent_map_id != null
                  return = {type: "list"}
                } as $cur_lenses
              
                foreach ($cur_lenses) {
                  each as $ln {
                    conditional {
                      if ($ln.agent_map_id != null && !($visited|contains:$ln.agent_map_id)) {
                        var.update $visited {
                          value = $visited|push:$ln.agent_map_id
                        }
                      
                        var.update $next_frontier {
                          value = $next_frontier|push:$ln.agent_map_id
                        }
                      
                        var.update $links_out {
                          value = $links_out
                            |push:```
                              {
                                source_map          : $cur_id
                                target_map          : $ln.agent_map_id
                                link_type           : "agent_manual"
                                label               : $ln.label
                                source_lens         : $ln.id
                                source_lens_label   : $ln.label
                                journey_architecture: $architecture_id
                              }
                              ```
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      
        var.update $depth {
          value = $depth + 1
        }
      
        var.update $frontier {
          value = $next_frontier
        }
      
        conditional {
          if (($next_frontier|count) == 0) {
            var.update $walk_status {
              value = "complete"
            }
          }
        
          elseif ($depth >= $input.max_depth) {
            var.update $walk_status {
              value = "depth_capped"
            }
          
            var.update $walk_warnings {
              value = $walk_warnings
                |push:```
                  {
                    type  : "depth_cap"
                    detail: "BFS halted at max_depth=" ~ $input.max_depth ~ "; " ~ ($next_frontier|count) ~ " unexplored map(s)"
                  }
                  ```
            }
          }
        }
      }
    }
  }

  response = {
    root_map_id    : $input.root_map_id
    architecture_id: $architecture_id
    visited_map_ids: $visited
    links          : $links_out
    warnings       : $walk_warnings
    walk_status    : $walk_status
  }
}