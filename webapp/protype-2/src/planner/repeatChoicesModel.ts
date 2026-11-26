// REPEAT-2 — what a repeat carries, and a plan's archive / delete rules as the screen shows them.
// The server decides and re-checks all of it (repeat/build_plan, planner/delete_check); nothing
// here is trusted by the server. Pure functions only, so they can be tested without a browser.

/** What the planner ticked on the repeat window. */
export interface RepeatChoices {
  people: boolean;
  jobs: boolean;
  /** The days and the scheduled slots. Needs people: a slot sits on someone's day. */
  assignments: boolean;
}

export const DEFAULT_CHOICES: RepeatChoices = {people: true, jobs: true, assignments: true};

/** Assignments cannot be carried without people. */
export const assignmentsLocked = (c: RepeatChoices): boolean => !c.people;

/** Tick or untick one box. Unticking people also unticks assignments; assignments stays off while people is off. */
export function setChoice(c: RepeatChoices, key: keyof RepeatChoices, value: boolean): RepeatChoices {
  const next = {...c, [key]: value};
  if (!next.people) next.assignments = false;
  return next;
}

/**
 * The request body. SKIP flags on purpose: a caller that says nothing (the AI tool, an older
 * screen) sends none of them, an omitted flag reads as false on the server, and false means copy.
 */
export const choicesToRequest = (c: RepeatChoices) => ({
  skip_people: !c.people,
  skip_jobs: !c.jobs,
  skip_assignments: !c.assignments || !c.people,
});

const joinWords = (words: string[]): string =>
  words.length <= 1 ? words.join('') : `${words.slice(0, -1).join(', ')} and ${words[words.length - 1]}`;

/** One plain line under the boxes. */
export function choicesLine(c: RepeatChoices): string {
  const names: [keyof RepeatChoices, string][] = [['people', 'people'], ['jobs', 'jobs'], ['assignments', 'assignments']];
  const on = names.filter(([k]) => c[k]).map(([, n]) => n);
  const off = names.filter(([k]) => !c[k]).map(([, n]) => n);
  if (on.length === 0) return 'Only the plan itself is made: no people, no jobs, no assignments.';
  if (off.length === 0) return `Carrying over: ${joinWords(on)}.`;
  const left = joinWords(off);
  return `Carrying over: ${joinWords(on)}. ${left.charAt(0).toUpperCase()}${left.slice(1)} are left out.`;
}

/** The plan list: archived plans are hidden unless the planner asks to see them. */
export const visiblePlans = <T extends {isArchived?: boolean}>(plans: T[], showArchived: boolean): T[] =>
  showArchived ? plans : plans.filter(p => !p.isArchived);

/** Delete is offered to admins only. The server refuses everyone else whatever the screen shows. */
export const canDeletePlan = (isAdmin: boolean): boolean => isAdmin;

/** The server's answer to "may this plan be deleted, and what would go?" (GET workspace/{id}/delete-check). */
export interface DeleteCheck {
  allowed: boolean;
  code: string;
  message: string;
  name: string;
  counts: {people: number; days: number; jobs: number; steps: number; slots: number};
  /** True when the plan is a repeated copy: deleting it lets the original be repeated to that date again. */
  frees_repeat_date: boolean;
}

const n = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`;

/** What the confirm shows. A refused delete shows only the server's reason. */
export function deleteConfirmLines(check: DeleteCheck): string[] {
  if (!check.allowed) return [check.message];
  const c = check.counts;
  const lines = [
    `Delete "${check.name}"?`,
    `This removes ${n(c.people, 'person', 'people')}, ${n(c.days, 'day', 'days')}, ${n(c.jobs, 'job', 'jobs')} and ${n(c.slots, 'slot', 'slots')}.`,
    'This cannot be undone.',
  ];
  if (check.frees_repeat_date) lines.push('Its original can then be repeated to this date again.');
  return lines;
}
