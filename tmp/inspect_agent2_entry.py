import json, base64

with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data:
    if item.get('path') == 'agents/2_journey_map_assistant.xs':
        print('=== All keys in agent 2 entry ===')
        for k, v in item.items():
            if k == 'original':
                decoded = base64.b64decode(v).decode('utf-8')
                print(f'  original: {len(decoded.splitlines())} lines, conflicts={decoded.count("<<<<<<")}')
            elif isinstance(v, str) and len(v) > 100:
                # Could be another base64 field
                try:
                    decoded = base64.b64decode(v).decode('utf-8')
                    print(f'  {k} (base64 decoded): {len(decoded.splitlines())} lines, first 60: {repr(decoded[:60])}')
                except Exception:
                    print(f'  {k}: (string) {len(v)} chars, first 60: {repr(v[:60])}')
            else:
                print(f'  {k}: {repr(v)[:80]}')
        break
