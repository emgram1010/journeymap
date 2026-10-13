// OBS-1 (US-OBS-1-06, grouping) — Groups a failure/rejected event into an
// "issue" on read, with nothing duplicated in storage.
//
// MUST match the backend's ops/group_issues.xs formula exactly: the same
// three parts, in the same order, joined by "::", with "none" when there
// is no error code. If either side changes this formula, a fingerprint
// computed in the browser (for a future acknowledgement feature) would
// no longer match one computed by the server.
export interface FingerprintInput {
  feature: string | null | undefined;
  step: string | null | undefined;
  errorCode?: string | null;
}

export function fingerprint(input: FingerprintInput): string {
  const feature = input.feature ?? '';
  const step = input.step ?? '';
  const errorCode = input.errorCode ?? 'none';
  return `${feature}::${step}::${errorCode}`;
}
