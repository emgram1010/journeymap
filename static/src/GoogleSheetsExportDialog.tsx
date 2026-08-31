// US-GSE-1-05 — Google Sheets JSON export dialog.
// Loads the map bundle for the chosen map, runs buildGoogleSheetsRows, then
// presents the JSON for copy/download alongside the Apps Script importer code
// and 4-step paste instructions.

import {Check, Copy, Download, X} from 'lucide-react';
import {useEffect, useMemo, useState} from 'react';
import {APPS_SCRIPT_IMPORT_CODE, buildGoogleSheetsRows, serializeGoogleSheetsJson} from './exportGoogleSheetsJson';
import {loadJourneyMapBundle} from './xano';

interface Props {
  mapId: number;
  mapTitle: string;
  onClose: () => void;
  onError: (msg: string) => void;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || 'journey-map';

function CopyButton({text, label}: {text: string; label: string}) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={async () => {
        try { await navigator.clipboard.writeText(text); setCopied(true); setTimeout(() => setCopied(false), 1500); }
        catch { /* clipboard unavailable */ }
      }}
      className="inline-flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium rounded border border-zinc-200 hover:bg-zinc-50 text-zinc-700"
    >
      {copied ? <Check className="w-3 h-3 text-emerald-600" /> : <Copy className="w-3 h-3" />}
      {copied ? 'Copied' : label}
    </button>
  );
}

export function GoogleSheetsExportDialog({mapId, mapTitle, onClose, onError}: Props) {
  const [json, setJson] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [rowCount, setRowCount] = useState(0);
  const [colCount, setColCount] = useState(0);

  useEffect(() => {
    let cancelled = false;
    loadJourneyMapBundle(mapId)
      .then((bundle) => {
        if (cancelled) return;
        const rows = buildGoogleSheetsRows({
          mapTitle: bundle.journeyMap.title ?? mapTitle,
          stages: bundle.stages,
          lenses: bundle.lenses,
          cells: bundle.cells,
        });
        setJson(serializeGoogleSheetsJson(rows));
        setRowCount(rows.length);
        setColCount(rows[0] ? Object.keys(rows[0]).length : 0);
      })
      .catch((e) => { if (!cancelled) { onError(e instanceof Error ? e.message : 'Failed to build export'); onClose(); } })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [mapId, mapTitle, onClose, onError]);

  const filename = useMemo(() => `${slug(mapTitle)}-google-sheets.json`, [mapTitle]);

  const handleDownload = () => {
    if (!json) return;
    const blob = new Blob([json], {type: 'application/json'});
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-xl p-6 w-[640px] max-h-[90vh] overflow-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="text-sm font-semibold text-zinc-900">Export to Google Sheets (JSON)</h3>
            <p className="text-xs text-zinc-500 mt-0.5">From <span className="font-mono">m{mapId}</span> · {mapTitle}</p>
          </div>
          <button onClick={onClose} className="p-1 hover:bg-zinc-100 rounded text-zinc-400"><X className="w-4 h-4" /></button>
        </div>

        {loading && <div className="text-xs text-zinc-500 py-8 text-center">Building rows…</div>}

        {!loading && json && (
          <>
            <div className="mb-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400 mb-2">How to import (4 steps)</div>
              <ol className="text-xs text-zinc-700 space-y-1 list-decimal list-inside">
                <li>From inside a Google Sheet, open <span className="font-medium">Extensions → Apps Script</span> (this binds the script to the sheet).</li>
                <li>Paste the Apps Script code below into <code className="font-mono">Code.gs</code> and save.</li>
                <li>Back in the sheet, refresh, then run <span className="font-medium">Extensions → Macros → Import → importJSON</span>.</li>
                <li>A dialog opens with a paste box — paste the JSON below and click Import. The sheet is populated with frozen, bold headers and word wrap.</li>
              </ol>
            </div>

            <div className="mb-4">
              <div className="flex items-center justify-between mb-1.5">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400">Apps Script code</div>
                <CopyButton text={APPS_SCRIPT_IMPORT_CODE} label="Copy code" />
              </div>
              <pre className="text-[10.5px] leading-[1.45] bg-zinc-50 border border-zinc-200 rounded-lg p-3 max-h-44 overflow-auto font-mono text-zinc-800 whitespace-pre">{APPS_SCRIPT_IMPORT_CODE}</pre>
            </div>

            <div className="mb-4">
              <div className="flex items-center justify-between mb-1.5">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400">JSON · {rowCount} row{rowCount === 1 ? '' : 's'} · {colCount} column{colCount === 1 ? '' : 's'}</div>
                <div className="flex items-center gap-1.5">
                  <CopyButton text={json} label="Copy JSON" />
                  <button onClick={handleDownload} className="inline-flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-medium rounded border border-zinc-200 hover:bg-zinc-50 text-zinc-700">
                    <Download className="w-3 h-3" />Download
                  </button>
                </div>
              </div>
              <pre className="text-[10.5px] leading-[1.45] bg-zinc-50 border border-zinc-200 rounded-lg p-3 max-h-56 overflow-auto font-mono text-zinc-800 whitespace-pre">{json}</pre>
            </div>

            {json.length > 45000 && (
              <div className="mb-4 p-2.5 bg-amber-50 border border-amber-200 rounded-lg text-[11px] text-amber-800">
                JSON is {(json.length / 1000).toFixed(0)}k chars. Google's prompt input may truncate at ~50k — prefer the <span className="font-medium">Download</span> option and paste the file contents instead.
              </div>
            )}

            <div className="flex items-center justify-end">
              <button onClick={onClose} className="px-3 py-1.5 text-xs font-semibold bg-zinc-900 text-white rounded hover:bg-zinc-800">Done</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
