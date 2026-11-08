// PUX-4 (US-PUX-4-03) — one word for how far a job's PLANNING is, same colours
// everywhere (Jobs column, job panel). Computed by `jobPlanStatus`.
import type {JobPlanStatus} from '../jobScheduleModel';

const KIND_STYLE: Record<JobPlanStatus['kind'], string> = {
  unscheduled: 'bg-neutral-100 text-neutral-700 border-neutral-200',
  partly: 'bg-amber-50 text-amber-800 border-amber-200',
  scheduled: 'bg-blue-50 text-blue-800 border-blue-200',
  live: 'bg-emerald-50 text-emerald-800 border-emerald-200',
  done: 'bg-neutral-100 text-neutral-600 border-neutral-200',
  cancelled: 'bg-red-50 text-red-700 border-red-200',
};

export function JobPlanBadge({status, testId = 'job-plan-status'}: {status: JobPlanStatus; testId?: string}) {
  return (
    <span data-testid={testId} data-kind={status.kind} className={`inline-block rounded-full border px-2 py-0.5 text-[10px] font-semibold ${KIND_STYLE[status.kind]}`}>
      {status.label}
    </span>
  );
}
