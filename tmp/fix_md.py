with open('product/ai-assistant.md', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_block = [
    '  Never use the display label as the key \u2014 always use the key field from get_map_state.\n',
    '  Example: action="rename", key="s1", label="Browse Menu", stage_goal="Menu browsed and item selected.", primary_actor_lens="lens-2"\n',
    '\n',
    '- **Map has NO stages yet**:\n',
    '  Use stage_operations with action "add" for each new stage.\n',
    '  Example: action="add", label="Browse Menu", stage_goal="Menu browsed and item selected.", primary_actor_lens="lens-2"\n',
    '\n',
    'For both cases, infer stage_goal (one-sentence exit condition) and primary_actor_lens\n',
    '(lens key of the accountable actor) from the domain context and include them in every\n',
    'stage operation. If primary_actor_lens cannot be determined yet, omit it rather than guess.\n',
]

# Replace lines 513-547 (1-indexed) = indices 512-546 (0-indexed)
new_lines = lines[:512] + new_block + lines[547:]

with open('product/ai-assistant.md', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print('Done. Total lines:', len(new_lines))
