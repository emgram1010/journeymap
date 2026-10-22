// GUARD 1 (2026-10-18) — Every error code means exactly one thing.
//
// WHY THIS EXISTS. Building O4 I reached for `E-SCHED-002` and
// `E-SCHED-003` for "that day is published" and "work already
// recorded". Both codes already existed and already meant something
// else — "enter a duration between 1 and 1,440 minutes" and "someone
// else changed this". Nothing in the build would have caught it: the
// endpoint pushed cleanly, the messages read fine, and the tests
// passed. It was found by grepping the catalog by hand before wiring
// the UI, which is not a process — that is luck.
//
// A duplicated code is quietly expensive. The catalog is what support
// reads when someone quotes a code at them, so a code with two
// meanings sends the only support person in the business to the wrong
// answer with full confidence.
//
// WHAT IS CHECKABLE, AND WHAT IS NOT. Many backend messages are built
// by concatenation — `"'" ~ $map_title ~ "' hasn't been published
// yet. (E-JOB-003)"` — and there is no way to reconstruct the final
// string from source. Those are counted and skipped rather than
// guessed at. A message that is a COMPLETE literal can be compared
// exactly, and that is the shape my collision had, so the check that
// would have caught it is the one that runs.
//
// Pure functions over already-read text: the test does the file
// reading, so this stays testable without a filesystem.

/** `E-PLAN-012`, `E-SCHED-006` … */
export const CODE_PATTERN = /\bE-[A-Z0-9]+-\d+\b/g;

export interface CatalogEntry {
  code: string;
  feature: string;
  user_message: string;
  /**
   * Set when the wording is contextual BY DESIGN and only the code is
   * stable — `E-VAL-001` is "this is required" and the sentence names
   * the field. Without this the check would be wrong about a dozen
   * correct messages, and a guard that cries wolf gets switched off.
   * It is opt-in per entry, so a code can only escape the exact-match
   * check by someone deciding it should.
   */
  message_varies?: boolean;
  [key: string]: unknown;
}

export interface CodeUsage {
  code: string;
  /** The full literal the backend emits, or null when it is built by concatenation. */
  literalMessage: string | null;
  file: string;
  line: number;
}

/**
 * Every error code a backend source file emits, with its message when
 * that message is a single complete literal.
 *
 * A line containing `~` is a concatenation, so its text cannot be
 * known from source — the code is still recorded (so the "exists in
 * the catalog" check covers it) but with `literalMessage: null`.
 */
export function extractCodeUsages(source: string, file: string): CodeUsage[] {
  const out: CodeUsage[] = [];
  source.split('\n').forEach((line, i) => {
    const codes = line.match(CODE_PATTERN);
    if (!codes) return;
    // Comments describe codes without emitting them; a line that is
    // only a comment is documentation, not behaviour.
    if (line.trimStart().startsWith('//')) return;

    const isConcatenated = line.includes('~');
    // `value = "Some sentence. (E-FOO-001)"` → the quoted literal.
    const literal = isConcatenated ? null : line.match(/"([^"]*\(E-[A-Z0-9]+-\d+\))"/)?.[1] ?? null;

    for (const code of new Set(codes)) {
      out.push({code, literalMessage: literal, file, line: i + 1});
    }
  });
  return out;
}

/** The sentence without its trailing `(CODE)`, which is how the catalog stores it. */
export function stripCode(message: string): string {
  return message.replace(/\s*\(E-[A-Z0-9]+-\d+\)\s*$/, '').trim();
}

export interface RegistryProblem {
  kind: 'missing_from_catalog' | 'key_mismatch' | 'message_conflict';
  code: string;
  detail: string;
}

/**
 * Checks the catalog against how the backend actually uses each code.
 *
 *  - `missing_from_catalog`  a code is emitted that support cannot look up
 *  - `key_mismatch`          an entry's `code` field disagrees with its key
 *  - `message_conflict`      a code is emitted with wording the catalog
 *                            does not have — either the catalog is stale,
 *                            or the code has been reused for a second
 *                            meaning. THIS is the O4 collision.
 */
export function findRegistryProblems(
  catalog: Record<string, CatalogEntry>,
  usages: CodeUsage[],
): RegistryProblem[] {
  const problems: RegistryProblem[] = [];

  for (const [key, entry] of Object.entries(catalog)) {
    if (entry.code !== key) {
      problems.push({
        kind: 'key_mismatch',
        code: key,
        detail: `catalog key "${key}" but its code field says "${entry.code}"`,
      });
    }
  }

  for (const use of usages) {
    const entry = catalog[use.code];
    if (!entry) {
      problems.push({
        kind: 'missing_from_catalog',
        code: use.code,
        detail: `emitted by ${use.file}:${use.line} but absent from the catalog`,
      });
      continue;
    }
    if (use.literalMessage === null) continue; // built by concatenation — unknowable from source
    if (entry.message_varies === true) continue; // contextual by design — see CatalogEntry
    const emitted = stripCode(use.literalMessage);
    if (emitted !== entry.user_message.trim()) {
      problems.push({
        kind: 'message_conflict',
        code: use.code,
        detail:
          `${use.file}:${use.line} emits "${emitted}" but the catalog says "${entry.user_message}" — ` +
          `either the catalog is stale, or this code has been reused for a second meaning`,
      });
    }
  }

  return problems;
}

/**
 * GUARD 1b — the code that gets LOGGED and the code the user is SHOWN
 * must be the same one.
 *
 * Added immediately after making this exact mistake. Renumbering the
 * colliding codes, I changed every message —
 * `"One of those maps isn't available. (E-PLAN-015)"` — and left the
 * `reject_code` beside it saying `E-PLAN-004`. The user would have
 * been shown one code and the Health page would have recorded a
 * different one, which is worse than either being wrong on its own:
 * support reads the log, looks up the wrong entry, and confidently
 * explains the wrong failure.
 *
 * Nothing would have caught it. The message matched its catalog entry,
 * the code existed, the endpoint pushed cleanly. The only reason it
 * was found is that I happened to read the file before pushing.
 *
 * The house shape these endpoints all use is:
 *
 *     var.update $reject_code { value = "E-PLAN-015" }
 *     var.update $reject_msg  { value = "… (E-PLAN-015)" }
 *
 * so a message's code is matched against the nearest bare code
 * assignment above it.
 */
export function findCodePairingProblems(source: string, file: string): RegistryProblem[] {
  const lines = source.split('\n');
  const problems: RegistryProblem[] = [];
  const BARE = /value\s*=\s*"(E-[A-Z0-9]+-\d+)"\s*$/;
  const IN_MESSAGE = /value\s*=\s*.*\((E-[A-Z0-9]+-\d+)\)"/;

  lines.forEach((line, i) => {
    const shown = line.match(IN_MESSAGE)?.[1];
    if (!shown) return;
    for (let j = i - 1; j >= Math.max(i - 12, 0); j -= 1) {
      const logged = lines[j].match(BARE)?.[1];
      if (!logged) continue;
      if (logged !== shown) {
        problems.push({
          kind: 'message_conflict',
          code: shown,
          detail:
            `${file}:${i + 1} shows the user "${shown}" but the code recorded on line ${j + 1} ` +
            `is "${logged}" — support would look up the wrong failure`,
        });
      }
      return;
    }
  });

  return problems;
}
