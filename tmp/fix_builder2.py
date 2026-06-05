with open('agents/4_journey_map_builder.xs', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find where the first agent's guid line is
guid_line = None
for i, l in enumerate(lines):
    if 'guid = "bhPLLTqm0IEq4axKT00KTTPJ5I0"' in l:
        guid_line = i
        break

print(f'guid at line {guid_line + 1}')

# Keep only lines 0..guid_line (inclusive), then add closing }
# But first fix the duplicate "For ai_agent lenses" paragraph before the closing """
# Find the duplicate and remove one copy

first_def = lines[:guid_line + 1]

# Fix the duplicate "For ai_agent lenses" in the first definition
# Find it by looking for two consecutive occurrences
content = ''.join(first_def)
dup_marker = '      For ai_agent lenses, agent_map_id is set via update_actor_identity (lens-level field, not a cell field).\n      It points to the sub-journey map the Orchestrator runs when this actor is the primary actor at a stage.\n      \n      For ai_agent lenses, agent_map_id is set via update_actor_identity (lens-level field, not a cell field).\n      It points to the sub-journey map the Orchestrator runs when this actor is the primary actor at a stage.'

single = '      For ai_agent lenses, agent_map_id is set via update_actor_identity (lens-level field, not a cell field).\n      It points to the sub-journey map the Orchestrator runs when this actor is the primary actor at a stage.'

if dup_marker in content:
    content = content.replace(dup_marker, single, 1)
    print('Removed duplicate ai_agent paragraph')
else:
    print('Duplicate paragraph not found with exact match, trying alternate...')
    # Try without trailing whitespace variation
    alt = '      For ai_agent lenses, agent_map_id is set via update_actor_identity (lens-level field, not a cell field).\n      It points to the sub-journey map the Orchestrator runs when this actor is the primary actor at a stage.\n'
    count = content.count(alt)
    print(f'Found {count} occurrences of the paragraph')
    if count > 1:
        idx = content.find(alt)
        idx2 = content.find(alt, idx + len(alt) - 5)
        if idx2 != -1:
            content = content[:idx2] + content[idx2 + len(alt):]
            print('Removed one duplicate')

# Write: cleaned first definition + closing }
with open('agents/4_journey_map_builder.xs', 'w', encoding='utf-8') as f:
    f.write(content)
    f.write('}\n')

print('Done')

# Verify
with open('agents/4_journey_map_builder.xs', 'r') as f:
    final = f.read()
print(f'Total lines: {len(final.splitlines())}')
print(f'Conflict markers: {final.count("<<<<<<<")}')
agent_count = final.count('agent "Journey Map Builder"')
print(f'agent "Journey Map Builder" count: {agent_count}')
