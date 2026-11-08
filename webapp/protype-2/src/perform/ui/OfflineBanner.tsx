// EXEC-1 (US-EXEC-1-08) — a thin, honest banner. Deliberately does NOT
// say anything will "send later" or "sync once you're back" — this app
// has no offline queue (a non-goal, explicitly out of scope for this
// epic), so a tap made offline is simply refused, not saved for later.
// Saying otherwise would be lying to a performer about whether their
// work is recorded.
import {WifiOff} from 'lucide-react';

export default function OfflineBanner() {
  return (
    <div className="flex items-center justify-center gap-2 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-800">
      <WifiOff className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>You&apos;re offline. Changes won&apos;t save until you reconnect.</span>
    </div>
  );
}
