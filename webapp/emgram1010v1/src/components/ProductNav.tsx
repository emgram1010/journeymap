import { Calendar, Settings } from 'lucide-react';

interface ProductNavProps {
  currentView?: string;
  onOpenSettings: () => void;
}

export function ProductNav({ currentView = 'planner', onOpenSettings }: ProductNavProps) {
  return (
    <aside 
      id="product-rail-nav"
      className="w-16 shrink-0 bg-neutral-900 border-r border-neutral-800 flex flex-col items-center py-4 select-none z-20"
      aria-label="Product navigation"
    >
      {/* Brand Glyph */}
      <div 
        id="brand-glyph" 
        className="w-9 h-9 rounded-lg bg-neutral-800 border border-neutral-700 flex items-center justify-center text-white font-semibold text-base tracking-tighter shadow-sm mb-6"
        title="Emgram Business Process Planner"
      >
        <span className="text-zinc-100 font-bold font-mono">Em</span>
      </div>

      {/* Main Nav Items */}
      <nav className="flex flex-col items-center gap-2 w-full px-2 flex-1">
        <button
          id="nav-item-planner"
          className="w-10 h-10 rounded-md flex items-center justify-center text-white bg-neutral-800 border border-neutral-700/60 shadow-xs transition-colors"
          title="Process Planner (Active)"
          aria-current="page"
        >
          <Calendar className="w-5 h-5 text-zinc-100" />
        </button>
      </nav>

      {/* Footer Nav — Settings is back now that it's wired to real
          functionality (cost rates + model pricing), per Story D1's
          "restore only if/when they do something" rule. */}
      <div className="flex flex-col items-center gap-2 w-full px-2">
        <button
          id="nav-item-settings"
          type="button"
          onClick={onOpenSettings}
          className="w-10 h-10 rounded-md flex items-center justify-center text-neutral-400 hover:text-white hover:bg-neutral-800 transition-colors"
          title="Settings — rates & model pricing"
        >
          <Settings className="w-5 h-5" />
        </button>
      </div>
    </aside>
  );
}
