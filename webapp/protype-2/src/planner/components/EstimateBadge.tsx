// EST-1 (US-EST-1-06) — the small label next to a card's or step's
// minutes: amber "estimate incomplete" when a stage is missing a rate
// for something in the order; a plain "guess" when every rate used was
// a seed value rather than measured. Renders nothing for 'n/a' (a map
// with no Items row, or a per_order stage with nothing to estimate).
import {AlertTriangle} from 'lucide-react';

interface EstimateBadgeProps {
  status?: 'n/a' | 'complete' | 'incomplete';
  source?: 'n/a' | 'seed' | 'measured';
}

export function EstimateBadge({status, source}: EstimateBadgeProps) {
  if (status === 'incomplete') {
    return (
      <span
        className="inline-flex items-center gap-0.5 text-amber-700 shrink-0"
        title="Add the missing item to the map's Items row and publish a new version."
      >
        <AlertTriangle className="w-3 h-3" />
        estimate incomplete
      </span>
    );
  }

  if (status === 'complete' && source === 'seed') {
    return (
      <span className="text-neutral-400 shrink-0" title="This rate was typed on the map, not learned from real work yet.">
        guess
      </span>
    );
  }

  return null;
}
