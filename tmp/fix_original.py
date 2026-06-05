import json, base64, re

# Read current clean xs file
with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    clean_xs = f.read()

# Build the 'temp' version (what the server has after our manual reset)
temp_xs = re.sub(
    r'(system_prompt:\s*""")(.*?)(""")',
    lambda m: m.group(1) + '\n      temp\n      ' + m.group(3),
    clean_xs,
    flags=re.DOTALL
)

print('temp_xs lines:', len(temp_xs.splitlines()))
print('Has conflict markers:', '<<<<<<' in temp_xs or '=======' in temp_xs)

# Base64-encode the temp version
temp_b64 = base64.b64encode(temp_xs.encode('utf-8')).decode('ascii')

# Load objects.json
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Find agent 2 and update its original
updated = False
for item in data:
    if item.get('type') == 'agent' and item.get('path') == 'agents/2_journey_map_assistant.xs':
        old_decoded = base64.b64decode(item['original']).decode('utf-8')
        print('Old original had conflict markers:', '<<<<<<' in old_decoded)
        print('Old original Stage Contract count:', old_decoded.count('## Stage Contract'))
        item['original'] = temp_b64
        updated = True
        print('Updated original to temp version.')
        break

if not updated:
    print('ERROR: agent not found')
else:
    with open('.xano/branches/v1/objects.json', 'w', encoding='utf-8') as f:
        json.dump(data, f)
    print('objects.json saved.')

# Verify
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data2 = json.load(f)
for item in data2:
    if item.get('type') == 'agent' and item.get('path') == 'agents/2_journey_map_assistant.xs':
        decoded = base64.b64decode(item['original']).decode('utf-8')
        print('New original has conflict markers:', '<<<<<<' in decoded or '=======' in decoded)
        print('New original Stage Contract count:', decoded.count('## Stage Contract'))
        print('Verification done.')
        break
