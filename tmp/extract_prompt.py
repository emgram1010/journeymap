with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    lines = f.readlines()
content_lines = lines[10:866]
stripped = []
for l in content_lines:
    if l.startswith('      '):
        stripped.append(l[6:])
    else:
        stripped.append(l)
with open('tmp/system_prompt_clean.txt', 'w', encoding='utf-8') as f:
    f.writelines(stripped)
content = ''.join(stripped)
print('Lines:', len(stripped))
print('Stage Contract:', content.count('## Stage Contract'))
print('Specialist Mode:', content.count('## Specialist Mode'))
print('Consortium Mode:', content.count('## Consortium Mode'))
placeholder = 'stage_goal="..."'
print('placeholder:', content.count(placeholder))
