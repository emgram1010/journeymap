// TAG-1 — the pure rules behind the tag chips and the tag filter. The server checks all of this
// again (functions/tags/tag_key.xs); these exist so the screen can say why before a round trip.

export interface MapTag {
  map_tag_id: number;
  name: string;
  map_count: number;
}

export interface MapTagLink {
  journey_map_id: number;
  map_tag_id: number;
}

export const TAG_NAME_MAX = 40;
export const TAGS_PER_MAP_MAX = 20;

/** "Ops", "ops" and " OPS " are one tag. Same rule as tags/tag_key. */
export function tagKey(name: string): string {
  return name.trim().toLowerCase();
}

/** Why this name cannot be a tag, or null when it can. */
export function tagNameProblem(name: string): string | null {
  const shown = name.trim();
  if (shown === '' || shown.length > TAG_NAME_MAX) return 'A tag needs a name of 1 to 40 characters.';
  if (shown.includes('<') || shown.includes('>')) return 'A tag name cannot contain < or >.';
  return null;
}

/** The tags one map carries, in name order. Links to a tag that no longer exists are ignored. */
export function tagsForMap(mapId: number, tags: MapTag[], links: MapTagLink[]): MapTag[] {
  const byId = new Map(tags.map((t) => [t.map_tag_id, t]));
  const out: MapTag[] = [];
  for (const link of links) {
    if (link.journey_map_id !== mapId) continue;
    const tag = byId.get(link.map_tag_id);
    if (tag && !out.some((t) => t.map_tag_id === tag.map_tag_id)) out.push(tag);
  }
  return out.sort((a, b) => tagKey(a.name).localeCompare(tagKey(b.name)));
}

/** Keep only the maps that carry the tag. tagId 0 means "no filter": every map comes back. */
export function filterByTag<T extends {id: number}>(maps: T[], links: MapTagLink[], tagId: number): T[] {
  if (!tagId) return maps;
  const tagged = new Set(links.filter((l) => l.map_tag_id === tagId).map((l) => l.journey_map_id));
  return maps.filter((m) => tagged.has(m.id));
}

/** Why a tag cannot be added to this map from the screen, or null when it can. */
export function addProblem(mapId: number, name: string, tags: MapTag[], links: MapTagLink[]): string | null {
  const nameProblem = tagNameProblem(name);
  if (nameProblem) return nameProblem;
  const mine = tagsForMap(mapId, tags, links);
  if (mine.some((t) => tagKey(t.name) === tagKey(name))) return 'This map already has that tag.';
  if (mine.length >= TAGS_PER_MAP_MAX) return 'This map already has 20 tags, the most allowed.';
  return null;
}
