import json, base64

with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Fix agent 4 baseline - show current state first
for item in data:
    if item.get('path') == 'agents/4_journey_map_builder.xs':
        orig_b64 = item.get('original', '')
        decoded = base64.b64decode(orig_b64).decode('utf-8')
        lines = decoded.splitlines()
        print('Agent 4 baseline lines:', len(lines))
        print('Conflict count:', decoded.count('<<<<<<<'))
        # Find and show conflict lines
        for i, l in enumerate(lines):
            if '<<<<<<<' in l or '=======' in l or '>>>>>>>' in l:
                start = max(0, i-2)
                end = min(len(lines), i+3)
                for j in range(start, end):
                    print(f'  [{j+1}]: {lines[j]}')
        break

# Now read local agent 4 file to use as the correct baseline
with open('agents/4_journey_map_builder.xs', 'r', encoding='utf-8') as f:
    local_content = f.read()

local_lines = local_content.splitlines()
print('\nLocal agent 4 lines:', len(local_lines))
print('Local conflicts:', local_content.count('<<<<<<<'))

# Update baseline to match local (clean) version
new_b64 = base64.b64encode(local_content.encode('utf-8')).decode('ascii')
updated = False
for item in data:
    if item.get('path') == 'agents/4_journey_map_builder.xs':
        item['original'] = new_b64
        updated = True
        print('\nUpdated agent 4 baseline to local clean version.')
        break

if updated:
    with open('.xano/branches/v1/objects.json', 'w', encoding='utf-8') as f:
        json.dump(data, f)
    print('objects.json saved.')

# Verify
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data2 = json.load(f)
for item in data2:
    if item.get('path') == 'agents/4_journey_map_builder.xs':
        decoded2 = base64.b64decode(item['original']).decode('utf-8')
        print('Verified: conflicts in new baseline:', decoded2.count('<<<<<<<'))
        print('Verified: lines:', len(decoded2.splitlines()))
        break
