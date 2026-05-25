import {useEffect, useRef, useState} from 'react';
import type {Stage, Lens} from './types';

type StageEditData = {
  label: string;
  primaryActorLens: string | null;
  stageGoal: string | null;
};

type Props = {
  stage: Stage;
  lenses: Lens[];
  onSave: (data: StageEditData) => void;
  onClose: () => void;
  isSaving: boolean;
};

export function StageEditPanel({stage, lenses, onSave, onClose, isSaving}: Props) {
  const [label, setLabel] = useState(stage.label);
  const [primaryActorLens, setPrimaryActorLens] = useState(stage.primaryActorLens ?? '');
  const [stageGoal, setStageGoal] = useState(stage.stageGoal ?? '');
  const overlayRef = useRef<HTMLDivElement>(null);

  // Close on Escape
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);

  // Close on click-outside
  const handleOverlayClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === overlayRef.current) onClose();
  };

  const handleSave = () => {
    if (!label.trim()) return;
    onSave({
      label: label.trim(),
      primaryActorLens: primaryActorLens || null,
      stageGoal: stageGoal.trim() || null,
    });
  };

  return (
    <div
      ref={overlayRef}
      onClick={handleOverlayClick}
      className="fixed inset-0 z-50 flex items-start justify-end bg-black/20"
    >
      <div className="w-[380px] h-full bg-white border-l border-zinc-200 shadow-xl flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-200">
          <h2 className="text-sm font-semibold text-zinc-900">Edit Stage</h2>
          <button
            onClick={onClose}
            className="text-zinc-400 hover:text-zinc-700 text-lg leading-none"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-5 space-y-5">
          {/* Stage Name */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Stage Name
            </label>
            <input
              type="text"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900"
              placeholder="e.g. Receive Intake"
            />
          </div>

          {/* Primary Actor */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Primary Actor
            </label>
            <select
              value={primaryActorLens}
              onChange={(e) => setPrimaryActorLens(e.target.value)}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900 bg-white"
            >
              <option value="">— None —</option>
              {lenses.map((l) => (
                <option key={l.id} value={l.key ?? l.id}>
                  {l.label}
                </option>
              ))}
            </select>
            <p className="mt-1 text-[10px] text-zinc-400">The actor accountable for this stage's outcome.</p>
          </div>

          {/* Stage Goal */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Stage Goal
            </label>
            <textarea
              value={stageGoal}
              onChange={(e) => setStageGoal(e.target.value)}
              rows={4}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900 resize-none"
              placeholder="What must be TRUE when this stage is done?"
            />
            <p className="mt-1 text-[10px] text-zinc-400">One sentence exit condition — the definition of done for this stage.</p>
          </div>
        </div>

        {/* Footer */}
        <div className="px-5 py-4 border-t border-zinc-200 flex items-center justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-sm text-zinc-600 hover:text-zinc-900 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving || !label.trim()}
            className="px-4 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700 disabled:opacity-40 transition-colors"
          >
            {isSaving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
