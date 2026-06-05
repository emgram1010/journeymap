with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()
print('Total lines:', len(lines))

# Check for conflict markers
for marker in ['<<<<<<<', '=======', '>>>>>>>']:
    count = content.count(marker)
    print(marker + ': ' + str(count))

# Check for placeholder triple-dot pattern inside quotes
placeholder = '"..."'
count = content.count(placeholder)
print('"...": ' + str(count))

# Find any line with three dots in quotes
for i, l in enumerate(lines):
    if '"..."' in l:
        print('  Line ' + str(i+1) + ': ' + l.strip())

# Find stage_goal lines
for i, l in enumerate(lines):
    if 'stage_goal' in l and 'Example' in l:
        print('stage_goal example at line ' + str(i+1) + ': ' + l.strip())
