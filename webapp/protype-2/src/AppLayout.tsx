import React, {useMemo, useState} from 'react';
import {NavLink, useLocation} from 'react-router-dom';
import {useAuth} from './AuthContext';
import {canManageTeam, hasModule, type ModuleKey} from './team/teamModel';
import {useMyModules} from './team/useMyModules';
import {Sparkles, CalendarRange, PlayCircle, Users, Boxes, BarChart3, Menu, X, ChevronDown, ChevronRight} from 'lucide-react';

/**
 * Persistent app chrome for every signed-in route.
 *
 * The sidebar stays mounted while the right pane navigates — architectures,
 * an architecture's detail, the journey map editor and the planner all render
 * inside it, so the menu never disappears as the user drills in.
 */

/* RPT-1 — a sub-item under a group header (Reports → Plan vs Action).
   It has no icon of its own: the group's icon stands for the group, and
   a second column of icons at this depth is noise. */
interface NavChild {
  id: string;
  label: string;
  to: string;
  matches: (pathname: string) => boolean;
}

interface NavItem {
  id: string;
  label: string;
  icon: React.ComponentType<{className?: string}>;
  to: string;
  matches: (pathname: string) => boolean;
  /* RPT-1. When present this item is a GROUP, not a link: it renders as a
     header that opens and closes, and only its children navigate. Keep
     `matches` covering the whole group's routes — it decides both the
     header's highlight and whether the group starts open. */
  children?: NavChild[];
  /* Omitted means everyone. Only the team item sets it, and the route guard
     and the endpoints enforce the same rule — this flag only decides
     whether the menu shows a door the person cannot open. */
  adminOnly?: boolean;
  /* USR-2. The module this item belongs to, if any. Same status as
     `adminOnly`: it decides what the menu SHOWS, and nothing else. The
     route guard turns a direct URL away and the endpoints behind it refuse
     on their own — hiding a menu item is not a permission. */
  module?: ModuleKey;
}

const NAV_ITEMS: NavItem[] = [
  {
    id: 'nav-intelligent-layer',
    label: 'Intelligent Layer',
    icon: Sparkles,
    to: '/architectures',
    /* The intelligent layer owns several routes (an architecture's detail, a
       journey map), so its highlight is prefix-based rather than exact. */
    matches: (p: string) =>
      p.startsWith('/architectures') || p.startsWith('/maps') || p.startsWith('/dashboard'),
    module: 'intelligence',
  },
  {
    id: 'nav-planner',
    label: 'Planner',
    icon: CalendarRange,
    to: '/planner',
    matches: (p: string) => p.startsWith('/planner'),
    module: 'planning',
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
    module: 'execution',
  },
  /* RPT-1 (2026-10-27): Reports, directly under Execution — these read
     what Execution recorded. A GROUP: "Reports" itself goes nowhere, and
     every report is one sub-item, so the next one is a line in `children`
     rather than another top-level entry.

     Gated on `planning`, NOT `execution`, even though it sits here: this
     report was reachable only through the planner's Jobs modal before the
     move, so anyone who could read it had the planning module. A move
     should not widen who can see something. Its endpoints (568 and the
     plan/job lists) enforce account tenancy on their own either way. */
  {
    id: 'nav-reports',
    label: 'Reports',
    icon: BarChart3,
    to: '/reports/plan-vs-action',
    matches: (p: string) => p.startsWith('/reports'),
    module: 'planning',
    children: [
      {
        id: 'nav-reports-plan-vs-action',
        label: 'Plan vs Action',
        to: '/reports/plan-vs-action',
        matches: (p: string) => p.startsWith('/reports/plan-vs-action'),
      },
    ],
  },
  /* USR-1 (2026-10-22): manage the people in the account.
     ADMIN-ONLY, changed the same day it was built. It first shipped visible
     to everyone, on the reasoning that the page renders no controls for a
     member so hiding the item would only cost an admin their own team until
     they learned the URL. The founder's instruction overrides that: "the
     only difference is that admins can have access to the user management
     module in their web interface." So the item is hidden for a member, the
     route turns them away, and — because hiding a menu item is not a
     permission — the five endpoints behind it each still enforce the admin
     check server-side, through `usr/assert_team_admin`. */
  {
    id: 'nav-team',
    label: 'Manage users',
    icon: Users,
    to: '/team',
    matches: (p: string) => p.startsWith('/team'),
    adminOnly: true,
  },
  /* CAT-1 (phase-6): the item-type / method catalog. No module gate and
     no adminOnly here — same reasoning /account uses: any signed-in
     member can see it and add to it (D-1); deactivate/delete are gated
     inside the page itself, by canManageTeam, not by hiding the menu
     item. Hiding the item would also hide it from the one person who
     set it up for someone else. */
  {
    id: 'nav-catalog',
    label: 'Catalog',
    icon: Boxes,
    to: '/settings/catalog',
    matches: (p: string) => p.startsWith('/settings/catalog'),
  },
];

/**
 * RPT-1 — a sidebar group with its own sub-items.
 *
 * The header is a BUTTON, not a link: "Reports" is not a page, and a
 * header that navigated somewhere would leave two things highlighted at
 * once (itself and the child it went to). It opens expanded — with one
 * report in it, starting closed would hide the only thing in the group
 * and cost a click every visit — and stays however the user last left
 * it, because the sidebar never unmounts.
 */
function NavGroup({item, pathname}: {item: NavItem; pathname: string}) {
  const {id, label, icon: Icon, matches, children = []} = item;
  const [open, setOpen] = useState(true);
  const isActive = matches(pathname);

  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        id={id}
        aria-expanded={open}
        aria-controls={`${id}-items`}
        onClick={() => setOpen((o) => !o)}
        className={`w-full flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
          isActive && !open ? 'bg-zinc-100 text-zinc-900' : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900'
        }`}
      >
        <Icon className="w-4 h-4 shrink-0" />
        <span className="flex-1 text-left">{label}</span>
        {open ? (
          <ChevronDown className="w-3.5 h-3.5 shrink-0 text-zinc-400" />
        ) : (
          <ChevronRight className="w-3.5 h-3.5 shrink-0 text-zinc-400" />
        )}
      </button>
      {open && (
        <div id={`${id}-items`} className="flex flex-col gap-1">
          {children.map((child) => {
            const childActive = child.matches(pathname);
            return (
              <NavLink
                key={child.id}
                id={child.id}
                to={child.to}
                aria-current={childActive ? 'page' : undefined}
                className={`w-full flex items-center rounded-lg pl-9 pr-3 py-1.5 text-sm transition-colors ${
                  childActive
                    ? 'bg-zinc-900 text-white font-medium'
                    : 'text-zinc-600 hover:bg-zinc-100 hover:text-zinc-900'
                }`}
              >
                {child.label}
              </NavLink>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default function AppLayout({children}: {children: React.ReactNode}) {
  const {pathname} = useLocation();
  const {user} = useAuth();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  /* `role` arrives on every page load from `auth/me` and, until USR-1, was
     never read. `canManageTeam` is the same function the Team page and its
     route guard use, so the three cannot drift into disagreeing about who
     counts as an admin. An untouched enum column reads back as "" rather
     than null, which is why that test lives in one place. */
  const isAdmin = canManageTeam(user);

  /* USR-2. `isLoading` matters: filtering before the answer arrives would
     draw an empty sidebar for a fraction of a second on every page load, and
     a menu that flickers is read as a bug. Everything shows until the answer
     is known, and the endpoints refuse anything that should not have been
     offered. */
  const {modules, isLoading: modulesLoading} = useMyModules();

  const navItems = useMemo(
    () =>
      NAV_ITEMS.filter((item) => {
        if (item.adminOnly && !isAdmin) return false;
        if (item.module == null || modulesLoading) return true;
        return hasModule({modules}, item.module);
      }),
    [isAdmin, modules, modulesLoading],
  );

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
        {navItems.map((item) => {
          const {id, label, icon: Icon, to, matches, children} = item;
          const isActive = matches(pathname);
          if (children && children.length > 0) {
            return <NavGroup key={id} item={item} pathname={pathname} />;
          }
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
          {navItems.map((item) => {
            const {id, label, icon: Icon, to, matches, children} = item;
            const isActive = matches(pathname);
            /* On a phone the whole menu is a one-shot sheet, so a group
               shows its children straight away — there is no room to
               spend a tap on a disclosure that closes again anyway. */
            if (children && children.length > 0) {
              return (
                <div key={id} className="flex flex-col gap-1">
                  <p className="flex items-center gap-3 px-3 pt-2 text-xs font-semibold uppercase tracking-wide text-zinc-400">
                    <Icon className="w-5 h-5 shrink-0" />
                    <span>{label}</span>
                  </p>
                  {children.map((child) => (
                    <NavLink
                      key={child.id}
                      id={`${child.id}-mobile`}
                      to={child.to}
                      onClick={() => setMobileNavOpen(false)}
                      aria-current={child.matches(pathname) ? 'page' : undefined}
                      className={`w-full flex items-center rounded-lg pl-11 pr-3 py-3 min-h-[44px] text-base font-medium ${
                        child.matches(pathname) ? 'bg-zinc-900 text-white' : 'text-zinc-700 hover:bg-zinc-100'
                      }`}
                    >
                      {child.label}
                    </NavLink>
                  ))}
                </div>
              );
            }
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
