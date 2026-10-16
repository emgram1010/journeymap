import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.tsx';
import AuthGate from './AuthGate.tsx';
import './index.css';

// PLN-9: gated on a real sign-in now, instead of rendering straight
// into a localStorage-seeded App. See AuthGate.tsx's own header for
// why this app needs its own login rather than borrowing protype-2's.
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthGate>{() => <App />}</AuthGate>
  </StrictMode>,
);
