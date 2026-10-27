import {listUserModuleAccess, type XanoUserModuleAccess} from '../xano';

/**
 * USR-2 — one in-flight fetch of the signed-in person's module grants,
 * shared by everything that asks.
 *
 * 🔴 THIS IS ITS OWN FILE TO AVOID A CIRCULAR IMPORT, not because it deserves
 * one. The cache has to be cleared on sign-out, which means `AuthContext` has
 * to call it — and `useMyModules` imports `useAuth` from `AuthContext`, so
 * putting the cache there would make the two import each other. Bundlers
 * sometimes tolerate that and sometimes hand you a half-initialised module at
 * runtime; a plain leaf module with no imports of its own cannot.
 *
 * Keyed by user id so that signing out and in as somebody else can never
 * serve the previous person's grants, even if the reset below were missed.
 */

interface CachedGrants {
  userId: number;
  promise: Promise<XanoUserModuleAccess[]>;
}

let cache: CachedGrants | null = null;

/**
 * The sidebar and every `ModuleRoute` ask on the same render, so without this
 * a single page load fires the request four or five times.
 */
export function fetchModuleGrants(userId: number): Promise<XanoUserModuleAccess[]> {
  if (cache == null || cache.userId !== userId) {
    cache = {userId, promise: listUserModuleAccess()};
  }
  return cache.promise;
}

/**
 * Called on sign-out, and after a failed fetch so the next render retries
 * rather than being handed the same rejected promise forever.
 */
export function resetModuleGrantsCache(): void {
  cache = null;
}
