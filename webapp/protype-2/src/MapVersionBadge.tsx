// GAP-FIX W6 (2026-10-17) — What is live, and have you changed it since?
//
// Before this, publishing a map showed a version number once, in a
// message that could be dismissed, and then nothing anywhere said which
// version a map was on, when it was published, or that the map had been
// edited since. `listMapVersions` existed and was never called from
// anywhere in the app.
//
// THE DANGEROUS ONE IS THE THIRD. A planner tidies up a step's wording,
// assumes it is live, and every plan keeps running the old frozen copy —
// which is exactly what freezing is FOR, and exactly why it has to be
// said out loud. The amber state is not an error; it is the system
// working, made visible.
//
// The decision itself (`has_unpublished_changes`) is the server's, and
// is a hash comparison through the same functions the publisher uses —
// never a second opinion computed here (see endpoint 521's own header).
import {useState} from 'react';
import {History, AlertTriangle, CheckCircle2} from 'lucide-react';
import type {MapVersionsResponse} from './xano';

function formatPublishedAt(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '';
  const ms = typeof value === 'number' ? value : Date.parse(value);
  if (Number.isNaN(ms)) return '';
  return new Date(ms).toLocaleDateString(undefined, {day: 'numeric', month: 'short'});
}

function formatPublishedAtLong(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return 'unknown date';
  const ms = typeof value === 'number' ? value : Date.parse(value);
  if (Number.isNaN(ms)) return 'unknown date';
  return new Date(ms).toLocaleString(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export default function MapVersionBadge({
  info,
  isLoading,
  onRefresh,
}: {
  info: MapVersionsResponse | null;
  isLoading: boolean;
  onRefresh: () => void;
}) {
  const [isOpen, setIsOpen] = useState(false);

  // No data yet, or a map that cannot have versions — say nothing rather
  // than show a badge that means nothing.
  if (!info && !isLoading) return null;

  const neverPublished = !!info && info.count === 0;
  const drifted = !!info?.has_unpublished_changes;

  const label = isLoading && !info
    ? 'Checking…'
    : neverPublished
      ? 'Never published'
      : drifted
        ? `v${info!.latest_version_no} · draft changes`
        : `v${info!.latest_version_no} · ${formatPublishedAt(info!.latest_published_at)}`;

  const tone = drifted
    ? 'border-amber-300 bg-amber-50 text-amber-800 hover:bg-amber-100'
    : neverPublished
      ? 'border-zinc-200 bg-white text-zinc-500 hover:bg-zinc-50'
      : 'border-zinc-200 bg-white text-zinc-600 hover:bg-zinc-50';

  return (
    <div className="relative">
      <button
        id="map-version-badge"
        type="button"
        onClick={() => {
          setIsOpen((v) => !v);
          if (!isOpen) onRefresh();
        }}
        title={
          drifted
            ? 'This map has been edited since it was last published. Live work still uses the published version.'
            : neverPublished
              ? 'This map has never been published, so no plan can use it yet.'
              : 'Version history'
        }
        className={`inline-flex items-center gap-1.5 rounded border px-2.5 py-1.5 text-[11px] font-medium transition-colors ${tone}`}
      >
        {drifted ? <AlertTriangle className="h-3.5 w-3.5" /> : <History className="h-3.5 w-3.5" />}
        {label}
      </button>

      {isOpen && info && (
        <div
          id="map-version-popover"
          className="absolute right-0 top-full z-50 mt-1.5 w-80 rounded-lg border border-zinc-200 bg-white p-3 text-[11px] shadow-xl"
        >
          {drifted ? (
            <p className="mb-2 flex items-start gap-1.5 rounded border border-amber-200 bg-amber-50 px-2 py-1.5 text-amber-900">
              <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />
              <span>
                You've changed this map since v{info.latest_version_no}. Plans keep using v{info.latest_version_no} until
                you publish again — that's deliberate, so work already underway can't change under anyone.
              </span>
            </p>
          ) : neverPublished ? (
            <p className="mb-2 text-zinc-600">
              Never published. A plan can't use this map until a version is frozen.
            </p>
          ) : (
            <p className="mb-2 flex items-start gap-1.5 text-emerald-700">
              <CheckCircle2 className="mt-0.5 h-3 w-3 shrink-0" />
              <span>What's on screen matches the published v{info.latest_version_no}.</span>
            </p>
          )}

          {info.versions.length > 0 && (
            <>
              <p className="mb-1 font-semibold text-zinc-700">Versions</p>
              <ul className="max-h-56 divide-y divide-zinc-100 overflow-y-auto rounded border border-zinc-100">
                {info.versions.map((v) => (
                  <li key={v.id} className="flex items-center justify-between gap-2 px-2 py-1.5">
                    <span className="font-medium text-zinc-800">v{v.version_no}</span>
                    <span className="text-zinc-500">{formatPublishedAtLong(v.published_at)}</span>
                    <span className="shrink-0 text-zinc-400">
                      {v.stage_count ?? 0} stage{(v.stage_count ?? 0) === 1 ? '' : 's'}
                    </span>
                  </li>
                ))}
              </ul>
            </>
          )}
        </div>
      )}
    </div>
  );
}
