// US-DEL-1-02 (2026-10-18) — The tables that hold the record, and must
// never be deleted from.
//
// WHY THIS EXISTS. Auditing map deletes turned up something worse than
// the orphans it was looking for: Execution survives a map delete ONLY
// because nothing has ever cleaned up `journey_map_version`. A job
// reads its instructions from that frozen snapshot, not from the live
// map, so deleting the map is harmless — and deleting the VERSION
// would silently strip the instructions from live and historical work.
// Nothing in the code said so. The safety was an accident, one
// well-meant tidy-up away from being lost.
//
// `schemaAudit.ts` already marks several of these `appendOnly`, but
// that check is about the table's SHAPE (no `updated_at`). It says
// nothing about whether code deletes rows. This is the other half.
//
// NOT EVERY APPEND-ONLY TABLE IS HERE, deliberately. A link table like
// `planner_task_work_task` is append-only in shape and still gets
// deleted legitimately — O4's unschedule removes one. The list below
// is narrower: tables that are the RECORD of something that happened.
// Deleting a row from any of them doesn't tidy the system up, it
// rewrites history.

export interface HistoryTable {
  table: string;
  /** Said in the terms of what breaks, not in schema terms. */
  why: string;
}

export const HISTORY_TABLES: HistoryTable[] = [
  {
    table: 'journey_map_version',
    why: "A job reads its instructions from this frozen snapshot. Delete one and live work loses the steps it was given — and finished work can no longer be explained.",
  },
  {
    table: 'stage_rate',
    why: "The rate card a version was published with. Estimates for every job pinned to that version read their minutes from here — delete a row and those estimates silently drop a line.",
  },
  {
    table: 'plan_publication',
    why: "The frozen copy of a day that was handed to someone. It is what the performer was actually told to do, and what variance is measured against.",
  },
  {
    table: 'activity_log',
    why: 'Every start, finish, block, skip and note. The only record of what was really done, and the input to every variance figure.',
  },
  {
    table: 'plan_change_log',
    why: 'What a planner changed after a day went live. Deleting it would make a published day look like it was always that way.',
  },
  {
    table: 'work_item_exception',
    why: "Why part of a job left for a linked map, from which step, and which counts went with it. It is the only link between a child job and the reason it exists — delete a row and Health can no longer say what an orphaned child came from.",
  },
  {
    table: 'event_log',
    why: 'The ops record behind the Health page. Support uses it to explain failures after the fact.',
  },
];

export const HISTORY_TABLE_NAMES: ReadonlySet<string> = new Set(HISTORY_TABLES.map((t) => t.table));

/**
 * The one way a history table may legitimately be deleted from, named
 * file by file.
 *
 * An allow-list rather than dropping the table from the list above:
 * `event_log` IS the ops record and must not be deleted from casually,
 * but it also cannot grow forever. RES-3-03 prunes it on a governed
 * retention policy — a `retention_policy` row sets the window and a
 * per-run cap, and disabling that row stops the prune without a
 * redeploy. That is a designed exception, so it is written down as
 * one. Anything NOT on this list fails the build.
 */
export interface AllowedDelete {
  /** Repo-relative path, exactly as the guard reports it. */
  file: string;
  table: string;
  why: string;
}

export const ALLOWED_DELETES: AllowedDelete[] = [
  {
    file: 'tasks/11_prune_event_log.xs',
    table: 'event_log',
    why: 'RES-3-03 retention prune: window and per-run cap come from the retention_policy table, and disabling that row stops it without a redeploy.',
  },
];

function isAllowed(file: string, table: string): boolean {
  return ALLOWED_DELETES.some((a) => a.file === file && a.table === table);
}

export interface DeleteViolation {
  table: string;
  file: string;
  line: number;
  why: string;
}

/**
 * Finds `db.del <history table>` in one backend source file.
 *
 * Matches the statement, not the word: `db.del journey_map_version {`
 * is a violation, a comment mentioning the table is not, and
 * `db.del journey_map {` must NOT match `journey_map_version` — hence
 * the word boundary on the table name.
 */
export function findHistoryDeletes(source: string, file: string): DeleteViolation[] {
  const out: DeleteViolation[] = [];
  source.split('\n').forEach((line, i) => {
    if (line.trimStart().startsWith('//')) return;
    const match = line.match(/\bdb\.del\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (!match) return;
    const table = match[1];
    if (!HISTORY_TABLE_NAMES.has(table)) return;
    if (isAllowed(file, table)) return;
    out.push({
      table,
      file,
      line: i + 1,
      why: HISTORY_TABLES.find((t) => t.table === table)!.why,
    });
  });
  return out;
}
