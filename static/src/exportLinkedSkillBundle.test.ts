// US-EXP-1-12 — Round-trip sanity test for the linked-skill bundle.
// Builds the canonical fixture graph, runs the full `buildLinkedSkillBundle`
// pipeline, re-reads the produced blob via JSZip, then asserts:
//   1. Every anchor referenced in any file resolves to a real map / stage /
//      lens / cell in the bundle (no dangling refs).
//   2. Every link in `_manifest.json` is reachable from `ARCHITECTURE.md`.
//   3. Every non-root README.md contains a valid origin block pointing at an
//      existing parent map.

import assert from 'node:assert/strict';
import test from 'node:test';
import JSZip from 'jszip';
import {buildLinkedSkillBundle} from './exportLinkedSkillBundle';
import {buildFixtureLinkedGraph} from './linkedGraphFixture';
import type {ManifestV1} from './exportLinkedManifest';

interface LoadedBundle {
  files: Record<string, string>;
  manifest: ManifestV1;
}

async function buildAndLoad(): Promise<LoadedBundle> {
  const graph = buildFixtureLinkedGraph();
  const result = await buildLinkedSkillBundle(graph, {traversal: 'all_linked'});
  assert.equal(result.cancelled, false, 'build should not be cancelled');
  assert.ok(result.blob, 'blob should be produced');

  const buffer = Buffer.from(await result.blob!.arrayBuffer());
  const zip = await JSZip.loadAsync(buffer);
  const files: Record<string, string> = {};
  await Promise.all(
    Object.values(zip.files).map(async (entry) => {
      if (entry.dir) return;
      files[entry.name] = await entry.async('string');
    }),
  );

  const manifestPath = Object.keys(files).find((p) => p.endsWith('/_manifest.json'));
  assert.ok(manifestPath, '_manifest.json must be present');
  const manifest = JSON.parse(files[manifestPath!]) as ManifestV1;
  return {files, manifest};
}

const MAP_ANCHOR_RE = /\[MAP:m(\d+)-[a-z0-9-]+\]/g;
const STAGE_ANCHOR_RE = /\[STAGE:m(\d+)-[a-z0-9-]+\/s(\d+)-[a-z0-9-]+\]/g;
const LENS_ANCHOR_RE = /\[LENS:m(\d+)-[a-z0-9-]+\/l(\d+)-[a-z0-9-]+\]/g;
const CELL_ANCHOR_RE = /\[CELL:m(\d+)-[a-z0-9-]+\/s(\d+)×l(\d+)\]/g;

test('bundle round-trip — fixture graph builds without warnings or cancellation', async () => {
  const {manifest} = await buildAndLoad();
  assert.equal(manifest.maps.length, 5, 'all 5 fixture maps emitted');
  assert.equal(manifest.links.length, 4, 'all 4 fixture edges emitted');
  assert.equal(manifest.root_map_id, 100);
  assert.equal(manifest.traversal, 'all_linked');
  assert.equal(manifest.warnings.length, 0, 'no warnings on a fully-hydrated fixture');
});

test('every anchor referenced in any bundle file resolves to a real entity', async () => {
  const {files, manifest} = await buildAndLoad();
  const knownMapIds = new Set(manifest.maps.map((m) => m.map_id));
  const sizeByMap = new Map(
    manifest.maps.map((m) => {
      // Use the fixture invariant: every map has 2 stages × 2 lenses.
      void m;
      return [m.map_id, {stages: 2, lenses: 2}] as const;
    }),
  );

  for (const [path, content] of Object.entries(files)) {
    if (!path.endsWith('.md')) continue;

    for (const m of content.matchAll(MAP_ANCHOR_RE)) {
      const id = Number(m[1]);
      assert.ok(knownMapIds.has(id), `${path}: dangling [MAP:m${id}] anchor`);
    }
    for (const m of content.matchAll(STAGE_ANCHOR_RE)) {
      const [, mapId, sIdx] = m;
      const dim = sizeByMap.get(Number(mapId));
      assert.ok(dim, `${path}: [STAGE] anchor points at unknown map m${mapId}`);
      assert.ok(Number(sIdx) >= 1 && Number(sIdx) <= dim!.stages, `${path}: stage index ${sIdx} out of range for m${mapId}`);
    }
    for (const m of content.matchAll(LENS_ANCHOR_RE)) {
      const [, mapId, lIdx] = m;
      const dim = sizeByMap.get(Number(mapId));
      assert.ok(dim, `${path}: [LENS] anchor points at unknown map m${mapId}`);
      assert.ok(Number(lIdx) >= 1 && Number(lIdx) <= dim!.lenses, `${path}: lens index ${lIdx} out of range for m${mapId}`);
    }
    for (const m of content.matchAll(CELL_ANCHOR_RE)) {
      const [, mapId, sIdx, lIdx] = m;
      const dim = sizeByMap.get(Number(mapId));
      assert.ok(dim, `${path}: [CELL] anchor points at unknown map m${mapId}`);
      assert.ok(Number(sIdx) >= 1 && Number(sIdx) <= dim!.stages, `${path}: cell stage index ${sIdx} out of range`);
      assert.ok(Number(lIdx) >= 1 && Number(lIdx) <= dim!.lenses, `${path}: cell lens index ${lIdx} out of range`);
    }
  }
});

test('every manifest link is reachable from ARCHITECTURE.md', async () => {
  const {files, manifest} = await buildAndLoad();
  const archPath = Object.keys(files).find((p) => p.endsWith('/ARCHITECTURE.md'));
  assert.ok(archPath, 'ARCHITECTURE.md must exist');
  const arch = files[archPath!];

  // Every map referenced by a link must be listed in the architecture index.
  const referencedMapIds = new Set<number>();
  for (const link of manifest.links) {
    referencedMapIds.add(link.source_map);
    referencedMapIds.add(link.target_map);
  }
  for (const mapId of referencedMapIds) {
    assert.match(arch, new RegExp(`\\[MAP:m${mapId}-[a-z0-9-]+\\]`), `ARCHITECTURE.md missing anchor for m${mapId}`);
  }
});

test('every non-root README.md carries a valid origin block to an existing parent map', async () => {
  const {files, manifest} = await buildAndLoad();
  const knownMapIds = new Set(manifest.maps.map((m) => m.map_id));

  for (const entry of manifest.maps) {
    const readmePath = Object.keys(files).find((p) => p.endsWith(`${entry.folder}/README.md`));
    assert.ok(readmePath, `README.md missing for ${entry.folder}`);
    const body = files[readmePath!];

    assert.match(body, /^---\n/, `${readmePath}: README must start with YAML frontmatter`);
    assert.match(body, new RegExp(`map_id: m${entry.map_id}\\b`), `${readmePath}: frontmatter map_id mismatch`);

    if (entry.map_id === manifest.root_map_id) {
      assert.match(body, /link_type: root/, `${readmePath}: root README must declare link_type: root`);
      continue;
    }

    assert.ok(entry.parent, `manifest entry for m${entry.map_id} should have a parent`);
    assert.match(body, /link_type: (sub_journey|exception|anti_journey|agent_manual|parent_child)/, `${readmePath}: non-root README must declare a non-root link_type`);
    const parentMatch = body.match(/parent_map: \[MAP:m(\d+)-[a-z0-9-]+\]/);
    assert.ok(parentMatch, `${readmePath}: missing parent_map anchor`);
    const parentId = Number(parentMatch![1]);
    assert.ok(knownMapIds.has(parentId), `${readmePath}: parent_map m${parentId} not in manifest`);
    assert.equal(parentId, entry.parent!.source_map, `${readmePath}: parent_map disagrees with manifest`);
  }
});
