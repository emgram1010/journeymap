// TAG-1 — tag chips on a map, and the tag filter above a list of maps. One hook holds the data
// (GET map_tags) and every change goes through POST map_tag_change; the server checks every rule
// again. What the person typed is kept when a save is refused.
import React, { useCallback, useEffect, useState } from 'react';
import { Pencil, Plus, Tag, Trash2, X } from 'lucide-react';
import { changeMapTag, friendlyError, getMapTags } from '../xano';
import { addProblem, tagNameProblem, tagsForMap, type MapTag, type MapTagLink } from './tagModel';

export interface MapTagsState {
  tags: MapTag[];
  links: MapTagLink[];
  error: string | null;
  clearError: () => void;
  add: (mapId: number, name: string) => Promise<boolean>;
  remove: (mapId: number, tagId: number) => Promise<void>;
  rename: (tagId: number, name: string) => Promise<boolean>;
  deleteTag: (tagId: number) => Promise<void>;
}

export function useMapTags(): MapTagsState {
  const [tags, setTags] = useState<MapTag[]>([]);
  const [links, setLinks] = useState<MapTagLink[]>([]);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    try {
      const data = await getMapTags();
      setTags(data.tags ?? []);
      setLinks(data.links ?? []);
    } catch {
      // Tags are a label, not the map: a failed load leaves the list usable without them.
      setTags([]);
      setLinks([]);
    }
  }, []);

  useEffect(() => { void reload(); }, [reload]);

  const add = async (mapId: number, name: string) => {
    const problem = addProblem(mapId, name, tags, links);
    if (problem) { setError(problem); return false; }
    try {
      await changeMapTag({ action: 'add', journey_map_id: mapId, name });
      setError(null);
      await reload();
      return true;
    } catch (err) {
      setError(friendlyError(err, 'The tag could not be added.'));
      return false;
    }
  };

  const remove = async (mapId: number, tagId: number) => {
    try {
      await changeMapTag({ action: 'remove', journey_map_id: mapId, map_tag_id: tagId });
      setError(null);
      await reload();
    } catch (err) {
      setError(friendlyError(err, 'The tag could not be removed.'));
    }
  };

  const rename = async (tagId: number, name: string) => {
    const problem = tagNameProblem(name);
    if (problem) { setError(problem); return false; }
    try {
      const first = await changeMapTag({ action: 'rename', map_tag_id: tagId, name });
      if (first.status === 'merge_needed') {
        const ok = window.confirm(
          `"${first.other_name}" already exists. Merge this tag into it? ${first.map_count} map(s) will show "${first.other_name}".`,
        );
        if (!ok) return false;
        await changeMapTag({ action: 'rename', map_tag_id: tagId, name, merge: true });
      }
      setError(null);
      await reload();
      return true;
    } catch (err) {
      setError(friendlyError(err, 'The tag could not be renamed.'));
      return false;
    }
  };

  const deleteTag = async (tagId: number) => {
    try {
      const first = await changeMapTag({ action: 'delete', map_tag_id: tagId });
      if (first.status === 'confirm_needed') {
        const ok = window.confirm(
          `${first.map_count} map(s) use "${first.name}". Delete the tag? The maps themselves are not changed.`,
        );
        if (!ok) return;
        await changeMapTag({ action: 'delete', map_tag_id: tagId, confirm: true });
      }
      setError(null);
      await reload();
    } catch (err) {
      setError(friendlyError(err, 'The tag could not be deleted.'));
    }
  };

  return { tags, links, error, clearError: () => setError(null), add, remove, rename, deleteTag };
}

/** The chips on one map, with a small "+ Tag" box. Clicks never open the map behind it. */
export function MapTagChips({ mapId, state }: { mapId: number; state: MapTagsState }) {
  const [adding, setAdding] = useState(false);
  const [value, setValue] = useState('');
  const mine = tagsForMap(mapId, state.tags, state.links);

  const commit = async () => {
    if (!value.trim()) { setAdding(false); return; }
    // Kept on a refusal, so the person can fix what they typed.
    if (await state.add(mapId, value)) { setValue(''); setAdding(false); }
  };

  return (
    <div className="flex items-center gap-1 flex-wrap" data-testid={`map-tags-${mapId}`} onClick={(e) => e.stopPropagation()}>
      {mine.map((t) => (
        <span key={t.map_tag_id} className="group/tag inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-sky-50 text-sky-800 text-[10px] font-medium">
          {t.name}
          <button
            title={`Remove tag ${t.name}`}
            aria-label={`Remove tag ${t.name}`}
            onClick={() => void state.remove(mapId, t.map_tag_id)}
            className="text-sky-400 hover:text-sky-900"
          >
            <X className="w-2.5 h-2.5" />
          </button>
        </span>
      ))}
      {adding ? (
        <input
          autoFocus
          value={value}
          maxLength={60}
          placeholder="Tag name"
          aria-label="New tag name"
          list="map-tag-names"
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') void commit(); if (e.key === 'Escape') { setAdding(false); setValue(''); } }}
          onBlur={() => void commit()}
          className="w-24 text-[10px] px-1.5 py-0.5 border border-zinc-300 rounded focus:outline-none focus:border-zinc-600"
        />
      ) : (
        <button
          title="Add a tag"
          onClick={() => { state.clearError(); setAdding(true); }}
          className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full border border-dashed border-zinc-300 text-[10px] text-zinc-500 hover:border-zinc-500 hover:text-zinc-800"
        >
          <Plus className="w-2.5 h-2.5" /> Tag
        </button>
      )}
      <datalist id="map-tag-names">
        {state.tags.map((t) => <option key={t.map_tag_id} value={t.name} />)}
      </datalist>
    </div>
  );
}

/** The filter row above a list of maps, with rename and delete for each tag behind "Manage". */
export function TagFilterBar({ state, selected, onSelect }: { state: MapTagsState; selected: number; onSelect: (tagId: number) => void }) {
  const [managing, setManaging] = useState(false);
  const [editingId, setEditingId] = useState(0);
  const [editValue, setEditValue] = useState('');

  if (state.tags.length === 0 && !state.error) return null;

  const saveRename = async (tagId: number) => {
    if (await state.rename(tagId, editValue)) setEditingId(0);
  };

  return (
    <div className="mb-5" data-testid="tag-filter-bar">
      <div className="flex items-center gap-1.5 flex-wrap text-xs">
        <Tag className="w-3.5 h-3.5 text-zinc-400" />
        <button
          onClick={() => onSelect(0)}
          className={`px-2.5 py-1 rounded-full border ${selected === 0 ? 'bg-zinc-900 text-white border-zinc-900' : 'bg-white text-zinc-600 border-zinc-200 hover:border-zinc-400'}`}
        >
          All
        </button>
        {state.tags.map((t) => (
          <button
            key={t.map_tag_id}
            onClick={() => onSelect(selected === t.map_tag_id ? 0 : t.map_tag_id)}
            className={`px-2.5 py-1 rounded-full border ${selected === t.map_tag_id ? 'bg-sky-700 text-white border-sky-700' : 'bg-white text-zinc-600 border-zinc-200 hover:border-zinc-400'}`}
          >
            {t.name} <span className="opacity-60">{t.map_count}</span>
          </button>
        ))}
        {state.tags.length > 0 && (
          <button onClick={() => setManaging((v) => !v)} className="ml-1 text-zinc-500 hover:text-zinc-900 underline">
            {managing ? 'Done' : 'Manage tags'}
          </button>
        )}
      </div>

      {state.error && (
        <div className="mt-2 flex items-start justify-between gap-3 px-3 py-2 bg-amber-50 border border-amber-200 rounded-lg text-xs text-amber-900" role="alert">
          <span>{state.error}</span>
          <button onClick={state.clearError} className="font-semibold hover:underline shrink-0">Dismiss</button>
        </div>
      )}

      {managing && (
        <ul className="mt-2 bg-white border border-zinc-200 rounded-lg divide-y divide-zinc-100 text-xs max-w-md">
          {state.tags.map((t) => (
            <li key={t.map_tag_id} className="flex items-center gap-2 px-3 py-2">
              {editingId === t.map_tag_id ? (
                <>
                  <input
                    autoFocus
                    value={editValue}
                    aria-label={`New name for ${t.name}`}
                    onChange={(e) => setEditValue(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') void saveRename(t.map_tag_id); if (e.key === 'Escape') setEditingId(0); }}
                    className="flex-1 px-1.5 py-0.5 border border-zinc-300 rounded focus:outline-none focus:border-zinc-600"
                  />
                  <button onClick={() => void saveRename(t.map_tag_id)} className="font-semibold text-zinc-800 hover:underline">Save</button>
                  <button onClick={() => setEditingId(0)} className="text-zinc-500 hover:underline">Cancel</button>
                </>
              ) : (
                <>
                  <span className="flex-1 text-zinc-800">{t.name}</span>
                  <span className="text-zinc-400">{t.map_count} map{t.map_count === 1 ? '' : 's'}</span>
                  <button title={`Rename ${t.name}`} onClick={() => { setEditingId(t.map_tag_id); setEditValue(t.name); }} className="text-zinc-400 hover:text-zinc-800">
                    <Pencil className="w-3.5 h-3.5" />
                  </button>
                  <button title={`Delete ${t.name}`} onClick={() => void state.deleteTag(t.map_tag_id)} className="text-zinc-400 hover:text-rose-600">
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
