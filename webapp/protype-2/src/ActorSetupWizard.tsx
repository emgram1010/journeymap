import {useEffect, useState} from 'react';
import {ChevronDown, ChevronUp, X} from 'lucide-react';
import {ACTOR_TEMPLATES} from './constants';
import type {ActorTemplate} from './constants';
import type {ActorType, Lens} from './types';

export interface ActorWizardInput {
  actorType: ActorType;
  templateKey: string;
  label: string;
  rolePrompt: string;
  personaDescription: string;
  primaryGoal: string;
  standingConstraints: string;
}

interface ActorSetupWizardProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: (input: ActorWizardInput) => Promise<void>;
  /** When provided, wizard opens in edit mode pre-populated with the lens values. */
  existingLens?: Lens | null;
}

export function ActorSetupWizard({isOpen, onClose, onConfirm, existingLens}: ActorSetupWizardProps) {
  const isEditMode = Boolean(existingLens?.actorType);

  const [selectedType, setSelectedType] = useState<ActorType | null>(existingLens?.actorType ?? null);
  const [label, setLabel] = useState(existingLens?.label ?? '');
  const [personaDescription, setPersonaDescription] = useState(existingLens?.personaDescription ?? '');
  const [primaryGoal, setPrimaryGoal] = useState(existingLens?.primaryGoal ?? '');
  const [standingConstraints, setStandingConstraints] = useState(existingLens?.standingConstraints ?? '');
  const [isRolePromptOpen, setIsRolePromptOpen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const activeTemplate: ActorTemplate | undefined = ACTOR_TEMPLATES.find((t) => t.actorType === selectedType);

  // Reset form when wizard opens/closes or switches lens
  useEffect(() => {
    if (isOpen) {
      setSelectedType(existingLens?.actorType ?? null);
      setLabel(existingLens?.label ?? '');
      setPersonaDescription(existingLens?.personaDescription ?? '');
      setPrimaryGoal(existingLens?.primaryGoal ?? '');
      setStandingConstraints(existingLens?.standingConstraints ?? '');
      setIsRolePromptOpen(false);
      setError(null);
      setIsLoading(false);
    }
  }, [isOpen, existingLens]);

  // Auto-fill label when an actor type is freshly selected in create mode
  const handleSelectType = (template: ActorTemplate) => {
    if (template.comingSoon) return;
    setSelectedType(template.actorType);
    if (!isEditMode && !label) {
      setLabel(template.label);
    }
    setError(null);
  };

  const handleConfirm = async () => {
    if (!selectedType || !activeTemplate) return;
    setError(null);
    setIsLoading(true);
    try {
      await onConfirm({
        actorType: selectedType,
        templateKey: activeTemplate.templateKey ?? '',
        label: label.trim() || activeTemplate.label,
        rolePrompt: activeTemplate.rolePrompt,
        personaDescription: personaDescription.trim(),
        primaryGoal: primaryGoal.trim(),
        standingConstraints: standingConstraints.trim(),
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
      setIsLoading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" onClick={onClose} />

      {/* Modal */}
      <div className="relative w-full max-w-lg bg-white rounded-xl shadow-2xl flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="h-14 flex items-center justify-between px-5 border-b border-zinc-200 shrink-0">
          <div>
            <span className="text-sm font-bold text-zinc-900">{isEditMode ? 'Edit Actor' : 'Add Actor Row'}</span>
            <p className="text-[10px] text-zinc-400 mt-0.5">
              {isEditMode ? 'Update actor identity and role context.' : 'Choose an actor type to define the role for this journey row.'}
            </p>
          </div>
          <button onClick={onClose} className="p-1.5 hover:bg-zinc-100 rounded text-zinc-400 transition-colors">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Scrollable body */}
        <div className="flex-1 overflow-y-auto p-5 space-y-5">
          {/* Actor type selector */}
          <div>
            <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-2">Actor Type</label>
            <div className="grid grid-cols-2 gap-2">
              {ACTOR_TEMPLATES.map((template) => {
                const isSelected = selectedType === template.actorType;
                return (
                  <button
                    key={template.actorType}
                    type="button"
                    onClick={() => handleSelectType(template)}
                    disabled={Boolean(template.comingSoon)}
                    className={`relative text-left p-3 rounded-lg border transition-all ${
                      template.comingSoon
                        ? 'border-zinc-100 bg-zinc-50 opacity-50 cursor-not-allowed'
                        : isSelected
                          ? 'border-zinc-900 bg-zinc-900 text-white shadow-sm'
                          : 'border-zinc-200 bg-white hover:border-zinc-400 hover:bg-zinc-50'
                    }`}
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <span className="text-base">{template.icon}</span>
                      <span className={`text-xs font-semibold ${isSelected ? 'text-white' : 'text-zinc-900'}`}>{template.label}</span>
                    </div>
                    <p className={`text-[10px] leading-snug ${isSelected ? 'text-zinc-300' : 'text-zinc-400'}`}>{template.description}</p>
                    {template.comingSoon && (
                      <span className="absolute top-2 right-2 text-[9px] font-bold uppercase tracking-wider text-zinc-400 bg-zinc-100 px-1.5 py-0.5 rounded">
                        Soon
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Config fields — shown once a type is selected */}
          {selectedType && (
            <>
              <div>
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Row Label</label>
                <input
                  type="text"
                  value={label}
                  onChange={(e) => setLabel(e.target.value)}
                  placeholder={activeTemplate?.label ?? 'Actor label'}
                  className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-400"
                />
              </div>

              <div>
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Persona Description</label>
                <textarea
                  value={personaDescription}
                  onChange={(e) => setPersonaDescription(e.target.value)}
                  placeholder="e.g. Residential homeowner, first-time appliance buyer"
                  rows={2}
                  className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-400 resize-none"
                />
              </div>

              <div>
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Primary Goal <span className="text-zinc-300">(Job-to-be-Done)</span></label>
                <textarea
                  value={primaryGoal}
                  onChange={(e) => setPrimaryGoal(e.target.value)}
                  placeholder="e.g. Purchase a replacement washer with minimal hassle and cost"
                  rows={2}
                  className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-400 resize-none"
                />
              </div>

              <div>
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Standing Constraints</label>
                <textarea
                  value={standingConstraints}
                  onChange={(e) => setStandingConstraints(e.target.value)}
                  placeholder="e.g. Only available weekends, home has staircase access only"
                  rows={2}
                  className="w-full p-2.5 bg-zinc-50 border border-zinc-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-zinc-400 resize-none"
                />
              </div>

              {/* Role prompt preview (collapsible) */}
              {activeTemplate?.rolePrompt && (
                <div className="border border-zinc-200 rounded-lg overflow-hidden">
                  <button
                    type="button"
                    onClick={() => setIsRolePromptOpen((o) => !o)}
                    className="w-full flex items-center justify-between px-3 py-2 bg-zinc-50 hover:bg-zinc-100 transition-colors"
                  >
                    <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Role Prompt Preview</span>
                    {isRolePromptOpen ? <ChevronUp className="w-3.5 h-3.5 text-zinc-400" /> : <ChevronDown className="w-3.5 h-3.5 text-zinc-400" />}
                  </button>
                  {isRolePromptOpen && (
                    <div className="px-3 py-2 bg-white">
                      <p className="text-[11px] text-zinc-500 leading-relaxed">{activeTemplate.rolePrompt}</p>
                    </div>
                  )}
                </div>
              )}
            </>
          )}

          {/* Error */}
          {error && <p className="text-xs text-rose-600 bg-rose-50 border border-rose-200 rounded p-2">{error}</p>}
        </div>

        {/* Footer */}
        <div className="shrink-0 border-t border-zinc-200 px-5 py-3 flex items-center justify-between bg-zinc-50 rounded-b-xl">
          <button
            type="button"
            onClick={onClose}
            disabled={isLoading}
            className="px-3 py-1.5 text-xs font-medium text-zinc-600 hover:text-zinc-900 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleConfirm()}
            disabled={!selectedType || isLoading}
            className="px-4 py-1.5 bg-zinc-900 text-white text-xs font-semibold rounded hover:bg-zinc-700 disabled:opacity-40 transition-colors"
          >
            {isLoading ? 'Saving...' : isEditMode ? 'Save Changes' : 'Add Actor'}
          </button>
        </div>
      </div>
    </div>
  );
}
