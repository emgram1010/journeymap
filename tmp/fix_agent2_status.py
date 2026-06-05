import json, base64, hashlib

# Read current local agent 2 file
with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    local_content = f.read()

print('Local file lines:', len(local_content.splitlines()))
print('Local file first 60:', repr(local_content[:60]))

# Compute SHA256 of local file (as bytes)
local_sha256 = hashlib.sha256(local_content.encode('utf-8')).hexdigest()
print('Local SHA256:', local_sha256)

# Load objects.json
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Find agent 2 entry and check
for item in data:
    if item.get('path') == 'agents/2_journey_map_assistant.xs':
        print('\nCurrent objects.json entry:')
        print('  status:', item.get('status'))
        print('  sha256 stored:', item.get('sha256'))
        print('  sha256 local:', local_sha256)
        print('  match:', item.get('sha256') == local_sha256)
        
        # Get SHA256 of the baseline (original)
        orig_b64 = item.get('original', '')
        orig_content = base64.b64decode(orig_b64).decode('utf-8')
        orig_sha256 = hashlib.sha256(orig_content.encode('utf-8')).hexdigest()
        print('  sha256 of baseline:', orig_sha256)
        
        # If local matches baseline, set status to 'unchanged' and update sha256
        if local_content.strip() == orig_content.strip():
            print('\nLocal matches baseline — fixing status to unchanged')
            item['status'] = 'unchanged'
            item['sha256'] = local_sha256
        else:
            print('\nLocal does NOT match baseline')
            print('  local lines:', len(local_content.splitlines()))
            print('  baseline lines:', len(orig_content.splitlines()))
        break

# Save
with open('.xano/branches/v1/objects.json', 'w', encoding='utf-8') as f:
    json.dump(data, f)
print('\nobjects.json saved.')

# Verify
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data2 = json.load(f)
for item in data2:
    if item.get('path') == 'agents/2_journey_map_assistant.xs':
        print('Verified status:', item.get('status'))
        print('Verified sha256:', item.get('sha256'))
        break
