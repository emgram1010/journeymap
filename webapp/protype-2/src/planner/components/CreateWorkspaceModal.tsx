// PLN-9 (US-PLN-9-07) — Start a real plan from a template.
//
// Replaces the old "New Workspace" flow's bare name-only prompt: a
// real plan now needs a template (its window length, default start
// time and accepted maps all come from there — PLAN-1's whole point)
// and a start date, not just a name.
import { useState, useEffect } from 'react';
import { X, FileStack } from 'lucide-react';
import type { TemplateListEntry } from '../plannerApi';

interface CreateWorkspaceModalProps {
  isOpen: boolean;
  templates: TemplateListEntry[];
  isLoadingTemplates: boolean;
  onClose: () => void;
  onCreate: (templateId: number, name: string, startDate: string) => Promise<boolean | void>;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

export function CreateWorkspaceModal({
  isOpen,
  templates,
  isLoadingTemplates,
  onClose,
  onCreate,
}: CreateWorkspaceModalProps) {
  const [name, setName] = useState('');
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [startDate, setStartDate] = useState(todayIso());
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    setName('');
    setStartDate(todayIso());
    setError(null);
    setTemplateId(templates[0]?.template.id ?? null);
  }, [isOpen, templates]);

  if (!isOpen) return null;

  const handleCreate = async () => {
    if (!name.trim()) {
      setError('Give the plan a name.');
      return;
    }
    if (!templateId) {
      setError('Choose a template to start from.');
      return;
    }
    setIsSaving(true);
    setError(null);
    const result = await onCreate(templateId, name.trim(), startDate);
    setIsSaving(false);
    if (result !== false) onClose();
    else setError('Could not create that plan — check the name isn’t already used.');
  };

  const selectedTemplate = templates.find(t => t.template.id === templateId);

  return (
    <div
      id="create-workspace-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
      onClick={onClose}
    >
      <div
        id="create-workspace-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-md flex flex-col overflow-hidden animate-in zoom-in-95 duration-100"
        onClick={e => e.stopPropagation()}
      >
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2">
            <FileStack className="w-4 h-4 text-neutral-900" />
            <h2 className="text-sm font-bold text-neutral-900">New plan from a template</h2>
          </div>
          <button type="button" onClick={onClose} className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-6 flex flex-col gap-4">
          <label className="flex flex-col gap-1">
            <span className="text-xs font-semibold text-neutral-700">Plan name</span>
            <input
              id="new-workspace-name-input"
              type="text"
              autoFocus
              value={name}
              onChange={e => { setName(e.target.value); setError(null); }}
              placeholder="e.g. Receiving — Nov batch"
              className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900"
            />
          </label>

          <label className="flex flex-col gap-1">
            <span className="text-xs font-semibold text-neutral-700">Template</span>
            {isLoadingTemplates ? (
              <span className="text-xs text-neutral-400">Loading templates…</span>
            ) : templates.length === 0 ? (
              <span className="text-xs text-neutral-500">
                No templates yet — a template needs to exist first (its own screen isn't built yet).
              </span>
            ) : (
              <select
                id="new-workspace-template-select"
                value={templateId ?? ''}
                onChange={e => setTemplateId(Number(e.target.value))}
                className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 bg-white"
              >
                {templates.map(t => (
                  <option key={t.template.id} value={t.template.id}>
                    {t.template.name} ({t.template.window_days}d, {t.maps.length} map{t.maps.length === 1 ? '' : 's'})
                  </option>
                ))}
              </select>
            )}
          </label>

          {selectedTemplate && (
            <p className="text-[11px] text-neutral-500 -mt-2">
              Maps: {selectedTemplate.maps.length > 0 ? selectedTemplate.maps.map(m => m.title).join(', ') : 'none yet'}
            </p>
          )}

          <label className="flex flex-col gap-1">
            <span className="text-xs font-semibold text-neutral-700">Start date</span>
            <input
              id="new-workspace-start-date-input"
              type="date"
              value={startDate}
              onChange={e => setStartDate(e.target.value)}
              className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
            />
          </label>

          {error && <p className="text-[11px] text-red-600">{error}</p>}
        </div>

        <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end gap-3 bg-neutral-50 shrink-0">
          <button type="button" onClick={onClose} className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50">
            Cancel
          </button>
          <button
            id="confirm-create-workspace-btn"
            type="button"
            onClick={handleCreate}
            disabled={isSaving || templates.length === 0}
            className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {isSaving ? 'Creating…' : 'Create plan'}
          </button>
        </div>
      </div>
    </div>
  );
}
