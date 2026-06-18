import {loadJourneyMapBundle, type HydratedJourneyMapBundle, type XanoJourneyMap} from './xano';
import type {Lens, MatrixCell, Stage} from './types';

const yesNo = (v: unknown) => (v === true ? 'yes' : v === false ? 'no' : '—');
const dash = (v: unknown) => {
  if (v === null || v === undefined) return '—';
  const s = String(v).trim();
  return s === '' ? '—' : s;
};
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || 'journey-map';

const settingsFields: Array<[keyof XanoJourneyMap, string]> = [
  ['primary_actor', 'Primary Actor'],
  ['journey_scope', 'Journey Scope'],
  ['start_point', 'Start Point'],
  ['end_point', 'End Point'],
  ['duration', 'Duration'],
  ['success_metrics', 'Success Metrics'],
  ['key_stakeholders', 'Key Stakeholders'],
  ['dependencies', 'Dependencies & Assumptions'],
  ['pain_points_summary', 'Pain Points Summary'],
  ['opportunities', 'Opportunities'],
  ['version', 'Version'],
];

function renderMatrixGrid(stages: Stage[], lenses: Lens[], cells: MatrixCell[]): string {
  if (stages.length === 0 || lenses.length === 0) return '_No matrix data._';
  const header = '| Lens \\ Stage | ' + stages.map((s) => s.key ?? s.id).join(' | ') + ' |';
  const sep = '|' + Array(stages.length + 1).fill('---').join('|') + '|';
  const rows = lenses.map((l) => {
    const cols = stages.map((s) => {
      const c = cells.find((x) => x.stageId === s.id && x.lensId === l.id);
      if (!c) return '⬜';
      if (c.isLocked) return '🔒';
      if (c.status === 'confirmed' && c.content) return '✅';
      if (c.content) return '◐';
      return '⬜';
    });
    return `| ${l.key ?? l.id} (${dash(l.label)}) | ${cols.join(' | ')} |`;
  });
  return [header, sep, ...rows].join('\n');
}

function renderActorFields(af: MatrixCell['actorFields']): string {
  if (!af || typeof af !== 'object') return '';
  const entries = Object.entries(af as Record<string, unknown>).filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '');
  if (entries.length === 0) return '';
  return ['', '**Actor fields:**', ...entries.map(([k, v]) => `- \`${k}\`: ${String(v).trim()}`)].join('\n');
}

export function buildJourneyMapMarkdown(bundle: HydratedJourneyMapBundle): string {
  const {journeyMap: m, stages, lenses, cells} = bundle;
  const filled = cells.filter((c) => c.content && c.content.trim() !== '').length;
  const confirmed = cells.filter((c) => c.status === 'confirmed').length;
  const locked = cells.filter((c) => c.isLocked).length;
  const total = stages.length * lenses.length;
  const now = new Date().toISOString();

  const lines: string[] = [];
  lines.push(`# ${m.title || 'Untitled Journey Map'}`, '');
  lines.push('> Journey Map exported for AI agent consumption.');
  lines.push(`> Generated: ${now}`);
  lines.push(`> Source: Emgram (journey_map_id=${m.id})`, '');

  lines.push('## Map Metadata');
  lines.push(`- ID: ${m.id}`);
  lines.push(`- Title: ${dash(m.title)}`);
  lines.push(`- Status: ${dash(m.status)}`);
  lines.push(`- Intent: ${dash(m.intent)}`);
  lines.push(`- Map Level: ${dash(m.map_level)}`);
  lines.push(`- Architecture: ${dash(m.journey_architecture)}`);
  lines.push(`- Parent Map: ${dash(m.parent_map_id)}`);
  lines.push(`- Cloned From: ${dash(m.cloned_from_map_id)}`);
  lines.push(`- Created: ${dash(m.created_at)}`);
  lines.push(`- Updated: ${dash(m.updated_at)}`, '');

  lines.push('## Map Context');
  for (const [key, label] of settingsFields) lines.push(`- ${label}: ${dash(m[key])}`);
  lines.push('');

  const sai = m.smart_ai_settings;
  if (sai) {
    lines.push('## Smart AI Behaviour');
    lines.push(`- Interview Depth: ${dash(sai.interview_depth)}`);
    lines.push(`- Insight Standard: ${dash(sai.insight_standard)}`);
    lines.push(`- Lens Priority: ${dash(sai.lens_priority)}`);
    lines.push(`- Emotional Mapping: ${yesNo(sai.emotional_mapping)}`);
    lines.push(`- Business Impact Framing: ${yesNo(sai.business_impact_framing)}`);
    lines.push(`- Auto-Confirm Writes: ${yesNo(sai.auto_confirm_writes)}`, '');
  }

  lines.push('## Stages (columns)');
  stages.forEach((s, i) => {
    lines.push(`${i + 1}. **${s.key ?? s.id}** — ${dash(s.label)}`);
    if (s.stageGoal) lines.push(`   - Goal: ${s.stageGoal}`);
    if (s.primaryActorLens) lines.push(`   - Primary Actor Lens: ${s.primaryActorLens}`);
  });
  lines.push('');

  lines.push('## Lenses / Actors (rows)');
  for (const l of lenses) {
    lines.push(`- **${l.key ?? l.id}** — ${dash(l.label)}${l.actorType ? ` _(actor_type: ${l.actorType})_` : ''}`);
    if (l.personaDescription) lines.push(`  - Persona: ${l.personaDescription}`);
    if (l.primaryGoal) lines.push(`  - Primary Goal: ${l.primaryGoal}`);
    if (l.standingConstraints) lines.push(`  - Constraints: ${l.standingConstraints}`);
    if (l.rolePrompt) lines.push(`  - Role Prompt: ${l.rolePrompt}`);
  }
  lines.push('');

  lines.push('## Cell Fill Grid');
  lines.push('Legend: ✅ confirmed · ◐ draft/filled · ⬜ empty · 🔒 locked', '');
  lines.push(renderMatrixGrid(stages, lenses, cells), '');

  lines.push('## Journey Matrix — Cell Content', '');
  for (const s of stages) {
    lines.push(`### Stage: ${dash(s.label)} (${s.key ?? s.id})`, '');
    for (const l of lenses) {
      const c = cells.find((x) => x.stageId === s.id && x.lensId === l.id);
      lines.push(`#### ${dash(l.label)} (${l.key ?? l.id})${l.actorType ? ` — ${l.actorType}` : ''}`);
      lines.push(`- Status: ${c?.status ?? 'empty'} · Locked: ${yesNo(c?.isLocked)}`);
      lines.push('');
      lines.push(c?.content && c.content.trim() !== '' ? c.content.trim() : '_empty_');
      const af = renderActorFields(c?.actorFields);
      if (af) lines.push(af);
      lines.push('');
    }
  }

  lines.push('## Fill Summary');
  lines.push(`- Total cells: ${total}`);
  lines.push(`- Filled: ${filled}`);
  lines.push(`- Empty: ${Math.max(total - filled, 0)}`);
  lines.push(`- Confirmed: ${confirmed}`);
  lines.push(`- Locked: ${locked}`, '');

  return lines.join('\n');
}

export async function exportJourneyMapMarkdown(journeyMapId: number, fallbackTitle?: string): Promise<void> {
  const bundle = await loadJourneyMapBundle(journeyMapId);
  const md = buildJourneyMapMarkdown(bundle);
  const filename = `${slug(bundle.journeyMap.title || fallbackTitle || `journey-map-${journeyMapId}`)}.md`;
  const blob = new Blob([md], {type: 'text/markdown;charset=utf-8'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
