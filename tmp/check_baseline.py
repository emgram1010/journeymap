import json, base64

with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

dotdotdot = '="..."'

for item in data:
    path = item.get('path', '')
    if 'journey_map_assistant' in path or '2_' in path:
        orig_b64 = item.get('original', '')
        if orig_b64:
            decoded = base64.b64decode(orig_b64).decode('utf-8')
            lines = decoded.splitlines()
            conflict_count = decoded.count('<<<<<<<')
            placeholder_count = decoded.count(dotdotdot)
            print('path:', path)
            print('lines:', len(lines))
            print('conflicts:', conflict_count)
            print('placeholders (="..."):', placeholder_count)
            print('first 100 chars:', repr(decoded[:100]))
            if conflict_count > 0:
                for i, l in enumerate(lines):
                    if '<<<<<<<' in l:
                        print('  conflict at line', i+1, ':', l.strip()[:80])
            if placeholder_count > 0:
                for i, l in enumerate(lines):
                    if dotdotdot in l:
                        print('  placeholder at line', i+1, ':', l.strip()[:80])
            print()
