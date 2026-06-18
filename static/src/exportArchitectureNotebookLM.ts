import JSZip from 'jszip';
import {loadJourneyMapBundle, type XanoJourneyArchitecture, type XanoJourneyMap} from './xano';
import {buildJourneyMapNotebookLM} from './exportMarkdownNotebookLM';

const snake = (s: string) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/(^_|_$)/g, '') || 'architecture';
const pad = (n: number, width: number) => String(n).padStart(width, '0');

export interface ArchExportProgress {
  total: number;
  done: number;
  current: string | null;
  ok: number;
  failed: number;
}

export interface ArchExportOptions {
  onProgress?: (p: ArchExportProgress) => void;
  shouldCancel?: () => boolean;
  concurrency?: number;
}

export interface ArchExportResult {
  ok: number;
  failed: number;
  cancelled: boolean;
  failures: Array<{id: number; title: string; reason: string}>;
}

function buildIndex(arch: XanoJourneyArchitecture, maps: XanoJourneyMap[], fileMap: Map<number, string>, failures: ArchExportResult['failures']): string {
  const lines: string[] = [];
  lines.push(`# Architecture: ${arch.title || 'Untitled Architecture'}`, '');
  lines.push(`This document indexes the journey maps that belong to the architecture "${arch.title || 'Untitled Architecture'}". Each map is exported as a separate Markdown source for ingestion into NotebookLM.`, '');
  lines.push('## Architecture Overview');
  lines.push(`- Title: ${arch.title ?? 'not set'}`);
  if (arch.description) lines.push(`- Description: ${arch.description}`);
  lines.push(`- Status: ${arch.status ?? 'not set'}`);
  lines.push(`- Total maps in architecture: ${maps.length}`);
  lines.push(`- Maps successfully exported: ${fileMap.size}`);
  lines.push(`- Maps that failed to export: ${failures.length}`, '');
  lines.push('## Included Journey Maps');
  lines.push('Each map below corresponds to a separate Markdown file in this bundle.', '');
  maps.forEach((m, i) => {
    const file = fileMap.get(m.id);
    if (file) lines.push(`${i + 1}. ${m.title || 'Untitled'} (file: ${file}, journey_map_id: ${m.id})`);
    else lines.push(`${i + 1}. ${m.title || 'Untitled'} (not exported, journey_map_id: ${m.id})`);
  });
  lines.push('');
  return lines.join('\n');
}

function buildErrors(failures: ArchExportResult['failures']): string {
  const lines: string[] = [];
  lines.push('# Export Errors', '');
  lines.push('The following journey maps could not be exported. They are not included as separate files in this bundle.', '');
  for (const f of failures) {
    lines.push(`## ${f.title || 'Untitled'} (journey_map_id: ${f.id})`);
    lines.push(`Reason: ${f.reason}`, '');
  }
  return lines.join('\n');
}

async function loadOne(map: XanoJourneyMap, shouldCancel?: () => boolean): Promise<{file: string; content: string} | {error: string}> {
  if (shouldCancel?.()) return {error: 'Cancelled before load.'};
  try {
    const bundle = await loadJourneyMapBundle(map.id, map);
    const content = buildJourneyMapNotebookLM(bundle);
    return {file: '', content};
  } catch (e) {
    const reason = e instanceof Error ? e.message : 'Unknown error';
    return {error: reason};
  }
}

function chunked<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

export async function exportArchitectureNotebookLM(
  arch: XanoJourneyArchitecture,
  maps: XanoJourneyMap[],
  opts: ArchExportOptions = {},
): Promise<ArchExportResult> {
  const concurrency = Math.max(1, opts.concurrency ?? 3);
  const width = String(maps.length).length;
  const fileMap = new Map<number, string>();
  const failures: ArchExportResult['failures'] = [];
  const zip = new JSZip();
  const root = zip.folder(`${snake(arch.title || 'architecture')}_notebooklm`)!;

  const progress: ArchExportProgress = {total: maps.length, done: 0, current: null, ok: 0, failed: 0};
  opts.onProgress?.({...progress});

  for (const batch of chunked(maps, concurrency)) {
    if (opts.shouldCancel?.()) {
      return {ok: progress.ok, failed: progress.failed, cancelled: true, failures};
    }
    const results = await Promise.all(batch.map(async (m) => ({map: m, result: await loadOne(m, opts.shouldCancel)})));
    for (const {map, result} of results) {
      progress.done += 1;
      progress.current = map.title ?? `Map ${map.id}`;
      if ('error' in result) {
        failures.push({id: map.id, title: map.title ?? '', reason: result.error});
        progress.failed += 1;
      } else {
        const index = progress.ok + 1;
        const filename = `journey_map_${pad(index, width)}_${snake(map.title || `map_${map.id}`)}.md`;
        root.file(filename, result.content);
        fileMap.set(map.id, filename);
        progress.ok += 1;
      }
      opts.onProgress?.({...progress});
    }
  }

  root.file('_index.md', buildIndex(arch, maps, fileMap, failures));
  if (failures.length > 0) root.file('_errors.md', buildErrors(failures));

  const blob = await zip.generateAsync({type: 'blob', streamFiles: true});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${snake(arch.title || 'architecture')}_notebooklm.zip`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);

  return {ok: progress.ok, failed: progress.failed, cancelled: false, failures};
}
