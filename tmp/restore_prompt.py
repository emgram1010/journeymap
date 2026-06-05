import re

with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    xs = f.read()

with open('tmp/system_prompt_clean.txt', 'r', encoding='utf-8') as f:
    clean_prompt = f.read().rstrip('\n')

# Indent each line of the prompt with 6 spaces
indented = '\n'.join('      ' + l if l else '' for l in clean_prompt.splitlines())

# Replace the system_prompt value (between the triple-quotes)
new_xs = re.sub(
    r'(system_prompt:\s*""")(.*?)(""")',
    lambda m: m.group(1) + '\n' + indented + '\n      ' + m.group(3),
    xs,
    flags=re.DOTALL
)

with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
    f.write(new_xs)

# Verify
with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    result = f.read()

print('Lines:', len(result.splitlines()))
print('Has conflict markers:', '<<<<<<' in result or '=======' in result)
print('Stage Contract count:', result.count('## Stage Contract'))
print('placeholder stage_goal:', result.count('stage_goal="..."'))
