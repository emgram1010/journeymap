import {useEffect, useState} from 'react';
import {useAuth} from '../AuthContext';
import {fetchModuleGrants, resetModuleGrantsCache} from './moduleGrantsCache';
import {mergeGrants, noModules, type ModuleGrants} from './teamModel';

/**
 * USR-2 (US-USR-2-05) — which modules the signed-in person holds.
 *
 * Read from `GET user_module_access` rather than from `auth/me`, deliberately.
 * `auth/me` is the highest-volume response in the app and has already been
 * fixed once for carrying more than it needed; one extra fetch on the pages
 * that gate themselves is the cheaper mistake. The endpoint is account-scoped
 * by the server, so the caller's own rows are simply the ones with their id.
 *
 * 🔴 ONE FETCH, SHARED, via `moduleGrantsCache`. The sidebar and every
 * `ModuleRoute` ask this question on the same render, so the promise is cached
 * per user id — without that, a single page load fires it four or five times.
 * The cache lives in its own leaf module so that `AuthContext` can clear it on
 * sign-out without the two files importing each other.
 *
 * 🔴 IT FAILS OPEN, AND THAT IS ON PURPOSE. If the fetch errors — a blip, a
 * 500, an expired token mid-flight — this reports every module as held. That
 * sounds exactly backwards for a permission, so the reasoning matters:
 *
 *   - This hook decides what the MENU SHOWS. It authorises nothing. Every
 *     endpoint behind every one of those doors runs `usr/assert_module_access`
 *     itself and refuses with E-USR-006 regardless of what the browser
 *     believes. The UI half must never be the thing that protects anything —
 *     the epic's second rule.
 *   - Failing closed would turn one failed request into an app with no
 *     navigation at all, and a user with real access being told to go and ask
 *     their admin. That is a worse, more confusing and less recoverable
 *     outcome than a menu item that refuses when clicked.
 *
 * So: closed on the server, open in the chrome. `failed` is returned so a
 * caller can say "we could not check" rather than pretend.
 */

export interface MyModules {
  modules: ModuleGrants;
  /** True until the answer is known. Gate nothing while this is true. */
  isLoading: boolean;
  /** The fetch failed, and `modules` is therefore the fail-open default. */
  failed: boolean;
}

const ALL_MODULES: ModuleGrants = {intelligence: true, planning: true, execution: true};

export function useMyModules(): MyModules {
  const {user} = useAuth();
  const userId = user?.id ?? 0;

  const [state, setState] = useState<MyModules>({
    modules: noModules(),
    isLoading: true,
    failed: false,
  });

  useEffect(() => {
    if (userId === 0) {
      setState({modules: noModules(), isLoading: false, failed: false});
      return;
    }

    let cancelled = false;
    setState((previous) => ({...previous, isLoading: true}));

    fetchModuleGrants(userId)
      .then((grants) => {
        if (cancelled) return;
        setState({
          modules: mergeGrants(grants).get(userId) ?? noModules(),
          isLoading: false,
          failed: false,
        });
      })
      .catch(() => {
        if (cancelled) return;
        // Fail open — see the header. The server still refuses.
        // Drop the rejected promise so the next render retries instead of
        // being handed the same failure forever.
        resetModuleGrantsCache();
        setState({modules: {...ALL_MODULES}, isLoading: false, failed: true});
      });

    return () => {
      cancelled = true;
    };
  }, [userId]);

  return state;
}
