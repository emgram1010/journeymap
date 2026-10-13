// VAL-1 — The shared junk corpus (epic Test Plan). Every value here is
// either something a rule MUST reject, or something it must accept once
// normalised. Used by both the rule-engine tests and, via the matching
// fixture in functions/validate_field.xs's tests, the backend.
export interface JunkCase {
  label: string;
  value: string;
  /** What should happen to a REQUIRED, unlimited-length text field. */
  expectedForRequiredText: 'reject' | 'accept';
}

export const TEXT_JUNK_CASES: JunkCase[] = [
  {label: 'empty', value: '', expectedForRequiredText: 'reject'},
  {label: 'spaces only', value: '   ', expectedForRequiredText: 'reject'},
  {label: 'tab and newline only', value: '\t\n\t', expectedForRequiredText: 'reject'},
  {label: 'null character', value: 'a\u0000b', expectedForRequiredText: 'accept'},
  {label: 'zero-width space', value: 'a​b', expectedForRequiredText: 'accept'},
  {label: '10000 characters', value: 'x'.repeat(10000), expectedForRequiredText: 'accept'},
  {label: 'script tag', value: '<script>alert(1)</script>', expectedForRequiredText: 'reject'},
  {label: 'bold tag', value: '<b>bold</b>', expectedForRequiredText: 'reject'},
  {label: 'sql-looking text', value: "Robert'); DROP TABLE students;--", expectedForRequiredText: 'accept'},
  {label: 'emoji', value: '🎉 party time', expectedForRequiredText: 'accept'},
  {label: 'very long single word', value: 'a'.repeat(500), expectedForRequiredText: 'accept'},
  {label: 'leading/trailing/multiple spaces', value: '  hello   world  ', expectedForRequiredText: 'accept'},
];

export interface NumberJunkCase {
  label: string;
  raw: string;
  /** Parsed value when valid, else null. */
  expectedValid: number | null;
}

export const NUMBER_JUNK_CASES: NumberJunkCase[] = [
  {label: 'negative', raw: '-1', expectedValid: -1},
  {label: 'zero', raw: '0', expectedValid: 0},
  {label: 'decimal', raw: '1.5', expectedValid: 1.5},
  {label: 'not a number', raw: 'abc', expectedValid: null},
  {label: 'NaN literal', raw: 'NaN', expectedValid: null},
  {label: 'huge exponent', raw: '1e999', expectedValid: null},
  {label: 'number with trailing letters', raw: '12abc', expectedValid: null},
];

export const INVALID_DATES: string[] = ['2026-02-31', '2026-13-01', '2026-00-10', 'not-a-date', ''];
export const VALID_DATES: string[] = ['2026-02-28', '2028-02-29' /* leap year */, '2026-01-01', '2026-12-31'];
