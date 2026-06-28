// US-EXP-1-15 — Linked NotebookLM bundle.
// Flat .zip of one Markdown file per visited map (no folder tree),
// + _index.md + _manifest.json. Reuses filterGraph + buildJourneyMapNotebookLM.

import JSZip from 'jszip';
import {mapSlug, slugify} from './exportAnchors';
import {buildLinkedManifest, serializeManifest, type ManifestV1, type ManifestWarning, type TraversalMode} from './exportLinkedManifest';
import {buildJourneyMapNotebookLM} from './exportMarkdownNotebookLM';
import {buildOriginBlock} from './exportOriginBlock';
import {filterGraph} from './exportLinkedSkillBundle';
import type {LinkedGraph} from './linkedGraphClient';

export interface LinkedNotebookLMOptions {
  traversal: TraversalMode;
  shouldCancel?: () => boolean;
}

export type LinkedNotebookLMProgress = (phase: 'building' | 'zipping', done: number, total: number) => void;

export interface LinkedNotebookLMResult {
  blob: Blob | null;
  filename: string;
  manifest: ManifestV1;
  cancelled: boolean;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function buildLinkedIndex(filtered: LinkedGraph, manifest: ManifestV1): string {
  const lines: string[] = [];
  const rootBundle = filtered.maps.get(filtered.rootMapId);
  const rootTitle = rootBundle?.journeyMap.title ?? `Map ${filtered.rootMapId}`;
  lines.push(`# Linked architecture: ${rootTitle}`, '');
  lines.push(`Root: m${filtered.rootMapId} · Traversal: ${manifest.traversal} · Maps included: ${manifest.maps.length}`, '');
  lines.push('## Reading order', '');
  filtered.bfsOrder.forEach((mapId, idx) => {
    const bundle = filtered.maps.get(mapId);
    const title = bundle?.journeyMap.title ?? `Map ${mapId}`;
    const file = `${pad2(idx + 1)}-${bundle ? mapSlug(bundle.journeyMap) : `m${mapId}`}.md`;
    lines.push(`${idx + 1}. **${title}** (file: \`${file}\`, journey_map_id: ${mapId})`);
  });
  lines.push('');
  if (manifest.warnings.length > 0) {
    lines.push('## Warnings', '');
    for (const w of manifest.warnings) lines.push(`- \`${w.type}\` — ${w.detail}`);
    lines.push('');
  }
  return lines.join('\n');
}

export async function buildLinkedNotebookLMBundle(
  graph: LinkedGraph,
  opts: LinkedNotebookLMOptions,
  onProgress?: LinkedNotebookLMProgress,
): Promise<LinkedNotebookLMResult> {
  const filtered = filterGraph(graph, opts.traversal);
  const extraWarnings: ManifestWarning[] = [];
  for (const mapId of filtered.bfsOrder) {
    if (!filtered.maps.has(mapId)) {
      extraWarnings.push({type: 'hydrate_missing', detail: `Map m${mapId} reached by walker but not hydrated; omitted from bundle.`});
    }
  }

  const manifest = buildLinkedManifest(filtered, {traversal: opts.traversal, extraWarnings});
  const totalMaps = filtered.bfsOrder.length;
  let done = 0;
  onProgress?.('building', done, totalMaps);

  const zip = new JSZip();
  const rootBundle = filtered.maps.get(filtered.rootMapId);
  const rootSlug = rootBundle ? mapSlug(rootBundle.journeyMap) : `m${filtered.rootMapId}`;
  const rootFolderName = slugify(rootBundle?.journeyMap.title ?? `journey-${filtered.rootMapId}`);
  const folder = zip.folder(`${rootFolderName}-notebooklm-linked`)!;
  const filename = `${rootSlug}-notebooklm-linked.zip`;

  for (let idx = 0; idx < filtered.bfsOrder.length; idx += 1) {
    if (opts.shouldCancel?.()) {
      return {blob: null, filename, manifest, cancelled: true};
    }
    const mapId = filtered.bfsOrder[idx];
    const bundle = filtered.maps.get(mapId);
    const fileName = `${pad2(idx + 1)}-${bundle ? mapSlug(bundle.journeyMap) : `m${mapId}`}.md`;

    if (!bundle) {
      folder.file(fileName, `# Map m${mapId}\n\n_Not hydrated. See \`_manifest.json\` warnings for detail._\n`);
      done += 1;
      onProgress?.('building', done, totalMaps);
      continue;
    }

    let body = buildJourneyMapNotebookLM(bundle);
    if (mapId !== filtered.rootMapId) {
      const origin = buildOriginBlock(filtered, mapId);
      if (origin) body = `${origin}\n${body}`;
    }
    folder.file(fileName, body);

    done += 1;
    onProgress?.('building', done, totalMaps);
  }

  if (opts.shouldCancel?.()) {
    return {blob: null, filename, manifest, cancelled: true};
  }

  folder.file('_index.md', buildLinkedIndex(filtered, manifest));
  folder.file('_manifest.json', serializeManifest(manifest));

  onProgress?.('zipping', 0, 1);
  const blob = await zip.generateAsync({type: 'blob', streamFiles: true});
  onProgress?.('zipping', 1, 1);

  return {blob, filename, manifest, cancelled: false};
}
