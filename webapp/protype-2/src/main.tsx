import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import {BrowserRouter, Routes, Route, Navigate, useParams} from 'react-router-dom';
import {AuthProvider, useAuth} from './AuthContext.tsx';
import Login from './Login.tsx';
import Register from './Register.tsx';
import Dashboard from './Dashboard.tsx';
import ArchitectureDashboard from './ArchitectureDashboard';
import ArchitectureDetail from './ArchitectureDetail';
import App from './App.tsx';
import AccountSettings from './AccountSettings.tsx';
import CatalogPage from './catalog/CatalogPage.tsx';
import TeamPage from './team/TeamPage.tsx';
import {canManageTeam, hasModule, type ModuleKey} from './team/teamModel';
import {useMyModules} from './team/useMyModules';
import NoAccessPage from './team/NoAccessPage.tsx';
import HealthPage from './health/HealthPage.tsx';
import {installGlobalErrorHandler} from './ops/globalErrorHandler';
import './index.css';

// OBS-1 (US-OBS-1-04): catch unhandled errors from anywhere in the app,
// as early as possible, so a crash still shows up on the Health page.
installGlobalErrorHandler();

/** Redirects to /login if the user is not authenticated; shows a loading screen while checking. */
function ProtectedRoute({children}: {children: React.ReactNode}) {
  const {user, isLoading} = useAuth();
  if (isLoading) {
    return (
      <div className="min-h-screen bg-zinc-50 flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-zinc-300 border-t-zinc-700 rounded-full animate-spin" />
          <span className="text-xs text-zinc-500">Checking session…</span>
        </div>
      </div>
    );
  }
  if (!user) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

/** Redirects already-authenticated users away from login/register. */
function PublicRoute({children}: {children: React.ReactNode}) {
  const {user, isLoading} = useAuth();
  if (isLoading) return null;
  if (user) return <Navigate to="/architectures" replace />;
  return <>{children}</>;
}

/**
 * OBS-1 (US-OBS-1-10): the Health page is for platform admins only. This
 * is a convenience redirect — every ops/* endpoint enforces the same
 * check server-side regardless of what this component does.
 */
function AdminRoute({children}: {children: React.ReactNode}) {
  const {user, isLoading} = useAuth();
  if (isLoading) return null;
  if (!user) return <Navigate to="/login" replace />;
  if (!user.is_platform_admin) return <Navigate to="/architectures" replace />;
  return <>{children}</>;
}

/**
 * USR-1 (2026-10-22) — the ACCOUNT admin gate, which is a different thing
 * from `AdminRoute` above.
 *
 * `is_platform_admin` spans every account and gates the Health page and the
 * cross-account ops tools. `role == "admin"` is per-account and gates the
 * people in your own account. Conflating the two would either lock the
 * founder's own admins out of their team or hand one account's admin the
 * platform tools, so they stay separate guards with separate names.
 *
 * A redirect, not a refusal page: the member has nothing to do here and no
 * decision to make. And this is a CONVENIENCE — hiding a menu item and
 * redirecting a route are not permissions. Every endpoint behind this page
 * runs `usr/assert_team_admin` itself, which logs the refusal and returns a
 * real 403.
 */
function AccountAdminRoute({children}: {children: React.ReactNode}) {
  const {user, isLoading} = useAuth();
  if (isLoading) return null;
  if (!user) return <Navigate to="/login" replace />;
  if (!canManageTeam(user)) return <Navigate to="/architectures" replace />;
  return <>{children}</>;
}

/**
 * USR-2 (US-USR-2-05) — the module gate for a route.
 *
 * A convenience, exactly like `AdminRoute` and `AccountAdminRoute`: it keeps
 * somebody from landing on a page whose every request will be refused. The
 * refusing is done by `usr/assert_module_access`, server-side, on every
 * endpoint in the module. Hiding a menu item and redirecting a route are not
 * permissions — the epic's second rule, and the reason the UI half must never
 * ship without the server half.
 *
 * 🔴 IT REDIRECTS TO `/no-access`, NEVER TO ANOTHER GATED ROUTE. Sending a
 * user with no grants to `/architectures` would bounce them off that gate and
 * back, forever. `/no-access` is signed-in-only and nothing redirects away
 * from it, which is what makes the chain terminate.
 *
 * While the answer is loading it renders nothing rather than guessing. A
 * redirect fired on incomplete information is the same bug as the loop, just
 * harder to see.
 */
function ModuleRoute({module, children}: {module: ModuleKey; children: React.ReactNode}) {
  const {user, isLoading} = useAuth();
  const {modules, isLoading: modulesLoading} = useMyModules();
  if (isLoading || modulesLoading) return null;
  if (!user) return <Navigate to="/login" replace />;
  if (!hasModule({modules}, module)) return <Navigate to="/no-access" replace />;
  return <>{children}</>;
}

/** Extracts `:id` from the URL and passes it to the editor. */
function MapEditorRoute() {
  const {id} = useParams<{id: string}>();
  const numericId = id ? Number(id) : undefined;
  return <App journeyMapId={numericId} />;
}

import React from 'react';
import AppLayout from './AppLayout';
import PlannerApp from './planner/PlannerApp';
import PerformToday from './perform/PerformToday';
import PlanVsActionPage from './reports/PlanVsActionPage';
import {PerformErrorBoundary} from './perform/PerformErrorBoundary';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
          <Route path="/register" element={<PublicRoute><Register /></PublicRoute>} />
          {/* USR-2 (2026-10-22): the three layers are now each a GRANT.
              `ModuleRoute` sits inside `ProtectedRoute` — sign-in first, then
              which rooms you may enter, and tenancy still after that on the
              server. These redirects are a convenience; the endpoints behind
              every one of these pages refuse on their own with E-USR-006. */}
          <Route path="/dashboard" element={<ProtectedRoute><ModuleRoute module="intelligence"><AppLayout><Dashboard /></AppLayout></ModuleRoute></ProtectedRoute>} />
          <Route path="/architectures" element={<ProtectedRoute><ModuleRoute module="intelligence"><AppLayout><ArchitectureDashboard /></AppLayout></ModuleRoute></ProtectedRoute>} />
          <Route path="/architectures/:id" element={<ProtectedRoute><ModuleRoute module="intelligence"><AppLayout><ArchitectureDetail /></AppLayout></ModuleRoute></ProtectedRoute>} />
          <Route path="/maps/:id" element={<ProtectedRoute><ModuleRoute module="intelligence"><AppLayout><MapEditorRoute /></AppLayout></ModuleRoute></ProtectedRoute>} />
          <Route path="/planner" element={<ProtectedRoute><ModuleRoute module="planning"><AppLayout><PlannerApp /></AppLayout></ModuleRoute></ProtectedRoute>} />
          {/* APP-1 was deliberately OUTSIDE AppLayout: the performer app is
              phone-first and wanted nothing to do with the desktop sidebar.
              That held until the sidebar gained an Execution item (PLN-9,
              2026-10-16) — a menu entry that navigates somewhere with no way
              back is worse than no entry. It is wrapped now, and the sidebar
              itself hides below `md`, so a performer on a phone still gets
              the full-width focused screen the original decision protected. */}
          <Route path="/perform" element={<ProtectedRoute><ModuleRoute module="execution"><AppLayout><PerformErrorBoundary><PerformToday /></PerformErrorBoundary></AppLayout></ModuleRoute></ProtectedRoute>} />
          {/* RPT-1 (2026-10-27): Reports. Planned vs actual moved here out
              of the planner's Jobs modal — same `planning` gate it had in
              there, so the move did not widen who can read it. `/reports`
              alone lands on the only report rather than a bare shell. */}
          <Route path="/reports" element={<Navigate to="/reports/plan-vs-action" replace />} />
          <Route path="/reports/plan-vs-action" element={<ProtectedRoute><ModuleRoute module="planning"><AppLayout><PlanVsActionPage /></AppLayout></ModuleRoute></ProtectedRoute>} />
          <Route path="/account" element={<ProtectedRoute><AppLayout><AccountSettings /></AppLayout></ProtectedRoute>} />
          {/* CAT-1 (phase-6): the item-type / method catalog. Same gate
              shape as /account — no module/admin route guard, because any
              signed-in member may add (D-1); deactivate/delete are gated
              per-action inside the page and the endpoints, not at the
              route. */}
          <Route path="/settings/catalog" element={<ProtectedRoute><AppLayout><CatalogPage /></AppLayout></ProtectedRoute>} />
          {/* USR-1: Manage users. ADMIN-ONLY, at the founder's instruction on
              2026-10-22 — "the only difference is that admins can have
              access to the user management module in their web interface."
              It shipped earlier the same day as a plain ProtectedRoute, on
              the reasoning that the page renders no controls for a member;
              that reasoning was sound and is overruled. A member typing the
              URL is sent to the architectures list. */}
          <Route path="/team" element={<AccountAdminRoute><AppLayout><TeamPage /></AppLayout></AccountAdminRoute>} />
          <Route path="/health" element={<AdminRoute><AppLayout><HealthPage /></AppLayout></AdminRoute>} />
          {/* USR-2: where somebody with no grants lands. SIGNED-IN ONLY,
              gated on nothing else, and nothing may ever redirect away
              from it — every other route is gated, so this is the only
              thing that stops the chain looping. */}
          <Route path="/no-access" element={<ProtectedRoute><AppLayout><NoAccessPage /></AppLayout></ProtectedRoute>} />
          {/* Default redirect */}
          <Route path="*" element={<Navigate to="/architectures" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
