// EXEC-1 (US-EXEC-1-09) — bottom tab bar: Today, Profile. No
// Notifications tab until that feature actually exists (README's
// Deferred table: a tab that's always empty teaches people to ignore
// it). Fixed at the very bottom, ABOVE each screen's own primary
// action bar (which sits at `bottom-14`, not `bottom-0`, once this
// exists) — see each screen's own comment at its action bar.
import {Calendar, User} from 'lucide-react';

export type PerformTab = 'today' | 'profile';

export default function PerformTabBar({active, onChange}: {active: PerformTab; onChange: (tab: PerformTab) => void}) {
  const items: {tab: PerformTab; label: string; icon: typeof Calendar}[] = [
    {tab: 'today', label: 'Today', icon: Calendar},
    {tab: 'profile', label: 'Profile', icon: User},
  ];
  return (
    <nav
      aria-label="Primary mobile navigation"
      className="fixed bottom-0 inset-x-0 z-20 flex h-14 border-t border-zinc-200 bg-white"
    >
      {items.map(({tab, label, icon: Icon}) => (
        <button
          key={tab}
          type="button"
          onClick={() => onChange(tab)}
          aria-label={`${label} tab`}
          aria-current={active === tab}
          className={`flex min-h-[44px] flex-1 flex-col items-center justify-center gap-0.5 text-xs font-medium ${
            active === tab ? 'text-zinc-900' : 'text-zinc-400'
          }`}
        >
          <Icon className="h-5 w-5" aria-hidden="true" />
          {label}
        </button>
      ))}
    </nav>
  );
}
