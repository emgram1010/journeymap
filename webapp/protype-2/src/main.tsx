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
import './index.css';

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
  if (user) return <Navigate to="/dashboard" replace />;
  return <>{children}</>;
}

/** Extracts `:id` from the URL and passes it to the editor. */
function MapEditorRoute() {
  const {id} = useParams<{id: string}>();
  const numericId = id ? Number(id) : undefined;
  return <App journeyMapId={numericId} />;
}

import React from 'react';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />
          <Route path="/register" element={<PublicRoute><Register /></PublicRoute>} />
          <Route path="/dashboard" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
          <Route path="/architectures" element={<ProtectedRoute><ArchitectureDashboard /></ProtectedRoute>} />
          <Route path="/architectures/:id" element={<ProtectedRoute><ArchitectureDetail /></ProtectedRoute>} />
          <Route path="/maps/:id" element={<ProtectedRoute><MapEditorRoute /></ProtectedRoute>} />
          {/* Default redirect */}
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
