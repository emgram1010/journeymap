import React, {useState} from 'react';
import {NavLink, useLocation} from 'react-router-dom';
import {Sparkles, CalendarRange, PlayCircle, Menu, X} from 'lucide-react';

/**
 * Persistent app chrome for every signed-in route.
 *
 * The sidebar stays mounted while the right pane navigates — architectures,
 * an architecture's detail, the journey map editor and the planner all render
 * inside it, so the menu never disappears as the user drills in.
 */

const NAV_ITEMS = [
  {
    id: 'nav-intelligent-layer',
    label: 'Intelligent Layer',
    icon: Sparkles,
    to: '/architectures',
    /* The intelligent layer owns several routes (an architecture's detail, a
       journey map), so its highlight is prefix-based rather than exact. */
    matches: (p: string) =>
      p.startsWith('/architectures') || p.startsWith('/maps') || p.startsWith('/dashboard'),
  },
  {
    id: 'nav-planner',
    label: 'Planner',
    icon: CalendarRange,
    to: '/planner',
    matches: (p: string) => p.startsWith('/planner'),
  },
  /* The third layer of the product. `/perform` has existed and worked
     since APP-1, but was reachable only by typing the URL — it was
     never in this menu, so nobody could get to it. Added 2026-10-16. */
  {
    id: 'nav-execution',
    label: 'Execution',
    icon: PlayCircle,
    to: '/perform',
    matches: (p: string) => p.startsWith('/perform'),
  },
];

export default function AppLayout({children}: {children: React.ReactNode}) {
  const {pathname} = useLocation();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  return (
    <div className="h-screen flex flex-col md:flex-row overflow-hidden bg-zinc-50 font-sans">
      <nav
        id="app-sidebar"
        aria-label="Main"
        /* Hidden below `md`: /perform is phone-first (APP-1) and now renders
           inside this layout, so on a phone the performer gets the full
           width and none of the desktop authoring chrome. The mobile top
           bar below replaces it so the other layers stay reachable. */
        className="hidden md:flex w-52 shrink-0 border-r border-zinc-200 bg-white px-3 py-4 flex-col gap-1"
      >
        {NAV_ITEMS.map(({id, label, icon: Icon, to, matches}) => {
          const isActive = matches(pathname);
          return (
            <NavLink
              key={id}
              id={id}
              to={to}
              aria-current={isActive ? 'page' : undefined}
              className={`w-full flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                isActive
                  ? 'bg-zinc-900 text-white'
                  : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900'
              }`}
            >
              <Icon className="w-4 h-4 shrink-0" />
              <span>{label}</span>
            </NavLink>
          );
        })}
      </nav>

      {/* Mobile top bar (US-APP-2-09): the sidebar above is hidden below
          `md`, so this hamburger is the only way to reach the other two
          layers from a phone. One tap opens the menu, one tap picks a
          layer — two taps total from anywhere. */}
      <div className="md:hidden flex items-center justify-between h-12 shrink-0 border-b border-zinc-200 bg-white px-3">
        <span className="text-sm font-semibold text-zinc-900">Emgram</span>
        <button
          type="button"
          aria-label={mobileNavOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={mobileNavOpen}
          onClick={() => setMobileNavOpen((open) => !open)}
          className="w-11 h-11 flex items-center justify-center -mr-1 text-zinc-700"
        >
          {mobileNavOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
      </div>

      {mobileNavOpen && (
        <div
          className="md:hidden fixed inset-0 top-12 z-40 bg-white flex flex-col gap-1 p-3 overflow-auto"
          role="dialog"
          aria-label="Navigation"
        >
          {NAV_ITEMS.map(({id, label, icon: Icon, to, matches}) => {
            const isActive = matches(pathname);
            return (
              <NavLink
                key={id}
                id={`${id}-mobile`}
                to={to}
                onClick={() => setMobileNavOpen(false)}
                aria-current={isActive ? 'page' : undefined}
                className={`w-full flex items-center gap-3 rounded-lg px-3 py-3 min-h-[44px] text-base font-medium ${
                  isActive
                    ? 'bg-zinc-900 text-white'
                    : 'text-zinc-700 hover:bg-zinc-100'
                }`}
              >
                <Icon className="w-5 h-5 shrink-0" />
                <span>{label}</span>
              </NavLink>
            );
          })}
        </div>
      )}

      {/* Right pane — owns its own scrolling so the sidebar never moves */}
      <div id="app-content" className="flex-1 min-w-0 min-h-0 overflow-auto">
        {children}
      </div>
    </div>
  );
}
