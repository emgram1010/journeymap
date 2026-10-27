// EXC-1 (US-EXC-1-08) — The line split: when part of a job leaves the
// happy path, which counts stay on the parent and which go to the
// child job.
//
// PURE. The backend twin is `functions/exceptions/split_lines.xs`; both
// run over `src/fixtures/exception-split-golden.json` (UT-EXC-1-01..04 here,
// FT-EXC-1-01 there). Change a rule in the fixture first, then both sides.
//
// RULES, in the order they are checked, per moved line, first bad line wins:
//   1. the item must be on the parent order            — E-EXC-005
//   2. the item must not be listed twice               — E-EXC-007
//   3. quantity is an integer, 1 ≤ q ≤ the parent line — E-EXC-006
// A line moved in full is REMOVED from the parent (D-4: EST-1 forbids a
// quantity of 0) and reported in `removed`. `flagged_quantity` is not
// touched — that is EXE-M-1's number, "handled in-house" (D-5).
//
// OUTPUT ORDER FOLLOWS THE PARENT'S LINES, never the request's, so the
// same move always produces the same arrays whichever order it was sent.
// An empty `moved` is a whole-job exception: nothing moves, not an error.

export type ParentLine = {item_type_id: number; item_key: string; quantity: number};
export type MovedLine = {item_type_id: number; quantity: number};
export type SplitCode = 'E-EXC-005' | 'E-EXC-006' | 'E-EXC-007';

export type SplitResult =
  | {ok: true; parentAfter: ParentLine[]; childLines: ParentLine[]; removed: number[]}
  | {ok: false; code: SplitCode; item_type_id: number};

const isWholeNumber = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);

export function splitLines(parentLines: ParentLine[], moved: MovedLine[]): SplitResult {
  const parentById = new Map<number, ParentLine>();
  for (const line of parentLines) parentById.set(line.item_type_id, line);

  const movedById = new Map<number, number>();
  for (const m of moved) {
    const id = m.item_type_id;
    const parentLine = isWholeNumber(id) ? parentById.get(id) : undefined;
    if (!parentLine) return {ok: false, code: 'E-EXC-005', item_type_id: id};
    if (movedById.has(id)) return {ok: false, code: 'E-EXC-007', item_type_id: id};
    const q = m.quantity;
    if (!isWholeNumber(q) || q < 1 || q > parentLine.quantity) {
      return {ok: false, code: 'E-EXC-006', item_type_id: id};
    }
    movedById.set(id, q);
  }

  const parentAfter: ParentLine[] = [];
  const childLines: ParentLine[] = [];
  const removed: number[] = [];
  for (const line of parentLines) {
    const q = movedById.get(line.item_type_id) ?? 0;
    if (q > 0) childLines.push({item_type_id: line.item_type_id, item_key: line.item_key, quantity: q});
    if (q === line.quantity) removed.push(line.item_type_id);
    else parentAfter.push({item_type_id: line.item_type_id, item_key: line.item_key, quantity: line.quantity - q});
  }
  return {ok: true, parentAfter, childLines, removed};
}
