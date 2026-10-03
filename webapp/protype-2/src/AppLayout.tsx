import React from 'react';
import {NavLink, useLocation} from 'react-router-dom';
import {Sparkles, CalendarRange} from 'lucide-react';

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
];

export default function AppLayout({children}: {children: React.ReactNode}) {
  const {pathname} = useLocation();

  return (
    <div className="h-screen flex overflow-hidden bg-zinc-50 font-sans">
      <nav
        id="app-sidebar"
        aria-label="Main"
        className="w-52 shrink-0 border-r border-zinc-200 bg-white px-3 py-4 flex flex-col gap-1"
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

      {/* Right pane — owns its own scrolling so the sidebar never moves */}
      <div id="app-content" className="flex-1 min-w-0 h-full overflow-auto">
        {children}
      </div>
    </div>
  );
}
