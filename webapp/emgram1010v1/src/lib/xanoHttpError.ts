// PLN-9 — `XanoHttpError` and `getAuthToken` kept byte-identical to
// the relevant pieces of webapp/protype-2/src/xano.ts on purpose (see
// EPIC-PLN-9-planner-frontend-wiring.md's "HTTP client" decision).
// Extracted into their own small file here rather than importing all
// of xano.ts, which is a large file full of journey-map-specific
// types this app has no use for.
export class XanoHttpError extends Error {
  status: number;
  /**
   * OBS-1 (US-OBS-1-12): the correlation id generated for this request.
   * Shown to the user as "Reference" so they can quote it. Until VAL-1's
   * standard error envelope exists, this is the id WE sent, not one the
   * server echoed back — still useful for finding the request on the
   * Health page's timeline by its own generated id.
   */
  reference: string;

  constructor(status: number, message: string, reference: string) {
    super(message);
    this.status = status;
    this.reference = reference;
    this.name = 'XanoHttpError';
  }
}

// Same key as protype-2's own `getAuthToken` for consistency, but
// NOT the same session automatically — `localStorage` is scoped per
// origin, and this app is deployed separately (Xano static hosting,
// its own domain). A user signs into this app's own login screen; the
// token it stores here never crosses into protype-2's or back, even
// though both hit the identical backend auth endpoints. One account,
// two separate browser sessions. Worth knowing before assuming
// "logged into one = logged into both".
export const getAuthToken = (): string | null => (typeof localStorage !== 'undefined' ? localStorage.getItem('authToken') : null);
