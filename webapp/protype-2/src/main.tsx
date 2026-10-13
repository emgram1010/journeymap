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

/** Extracts `:id` from the URL and passes it to the editor. */
function MapEditorRoute() {
  const {id} = useParams<{id: string}>();
  const numericId = id ? Number(id) : undefined;
  return <App journeyMapId={numericId} />;
}

import React from 'react';
import AppLayout from './AppLayout';
import PlannerApp from './planner/PlannerApp';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
          <Route path="/register" element={<PublicRoute><Register /></PublicRoute>} />
          <Route path="/dashboard" element={<ProtectedRoute><AppLayout><Dashboard /></AppLayout></ProtectedRoute>} />
          <Route path="/architectures" element={<ProtectedRoute><AppLayout><ArchitectureDashboard /></AppLayout></ProtectedRoute>} />
          <Route path="/architectures/:id" element={<ProtectedRoute><AppLayout><ArchitectureDetail /></AppLayout></ProtectedRoute>} />
          <Route path="/maps/:id" element={<ProtectedRoute><AppLayout><MapEditorRoute /></AppLayout></ProtectedRoute>} />
          <Route path="/planner" element={<ProtectedRoute><AppLayout><PlannerApp /></AppLayout></ProtectedRoute>} />
          <Route path="/account" element={<ProtectedRoute><AppLayout><AccountSettings /></AppLayout></ProtectedRoute>} />
          <Route path="/health" element={<AdminRoute><AppLayout><HealthPage /></AppLayout></AdminRoute>} />
          {/* Default redirect */}
          <Route path="*" element={<Navigate to="/architectures" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
