with open('agents/4_journey_map_builder.xs', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the conflict block start (line 25 area) and end (line 88 area)
# Strategy: find first <<<<<<< and last >>>>>>> in the block, replace with clean content

clean_stage_contract = """      ## Stage Contract awareness
      Every stage in the map has two optional contract fields you will see in get_map_state
      and get_slice responses:
      - **stage_goal**: the one-sentence exit condition / definition of done for this stage.
        Use it to ensure cell content you write is consistent with what the stage is trying
        to achieve. If a stage goal says "Intake parsed; name confirmed" and you are filling
        the internal row, your task_objective should align to that outcome.
      - **primary_actor_lens**: the lens key of the actor accountable for this stage's outcome.
        Use it to lead with that actor's perspective when content is ambiguous across lenses.

      You CAN write these fields using **update_stage_contract** during Phase 1 (scaffold phase)
      when explicitly instructed. After scaffold_structure creates the stages, call
      update_stage_contract for each stage to set stage_goal and primary_actor_lens before
      content fill begins. Always call get_map_state first to find journey_stage_id from
      stages[].xanoId and lens keys from cells[].lens_key.
      During content-fill phases (2-6), READ them from stage objects to inform cell quality.
"""

# Block 1: lines 25-88 area
# Find the first <<<<<<< 
idx_start = content.find('<<<<<<<\n<<<<<<<')
if idx_start == -1:
    idx_start = content.find('<<<<<<<')

# We want to replace from just before <<<<<<< back to the newline, and up to and including the closing >>>>>>>
# Find "      ## Core rules" which comes right after the last >>>>>>>
idx_core = content.find('      ## Core rules\n', idx_start)
idx_block_end = content.rfind('>>>>>>>\n', idx_start, idx_core)
idx_block_end_line_end = content.find('\n', idx_block_end) + 1

# Replace the conflict block
before = content[:idx_start]
after = content[idx_block_end_line_end:]
content = before + '\n' + clean_stage_contract + '\n' + after

# Block 2: agent_map_id whitespace conflict (simpler)
content = content.replace(
    'failures_scenarios, performance_metrics, model_owner, explainability_needs\n<<<<<<<\n\n      For ai_agent lenses',
    'failures_scenarios, performance_metrics, model_owner, explainability_needs\n\n      For ai_agent lenses'
)

# More general fix: remove any remaining conflict markers
lines = content.split('\n')
clean = []
for l in lines:
    s = l.strip()
    if s == '<<<<<<<' or s == '=======' or s == '>>>>>>>':
        continue
    clean.append(l)
content = '\n'.join(clean)

with open('agents/4_journey_map_builder.xs', 'w', encoding='utf-8') as f:
    f.write(content)

# Verify no conflict markers remain
remaining = [i+1 for i, l in enumerate(content.split('\n'))
             if l.strip() in ('<<<<<<<', '=======', '>>>>>>>')]
if remaining:
    print(f'WARNING: conflict markers still at lines: {remaining}')
else:
    print('Clean - no conflict markers')
