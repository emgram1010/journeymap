import {Lock} from 'lucide-react';
import {useAuth} from '../AuthContext';
import {useMyModules} from './useMyModules';
import {MODULES, MODULE_LABELS, hasModule} from './teamModel';

/**
 * USR-2 (US-USR-2-05) — where somebody with no modules lands.
 *
 * 🔴 THIS PAGE EXISTS TO TERMINATE A REDIRECT CHAIN, which is the one way
 * this story can fail badly. Every other route in the app is gated: a user
 * with no grants sent to `/architectures` is bounced, and bounced again, for
 * as long as the browser will let it. So this route is deliberately NOT gated
 * on anything beyond being signed in, and nothing may ever redirect away from
 * it.
 *
 * It tells the person what to ask for, rather than apologising. The only
 * useful action is a sentence they can send their admin, so that is what it
 * gives them.
 */
export default function NoAccessPage() {
  const {user} = useAuth();
  const {modules, isLoading, failed} = useMyModules();

  const granted = MODULES.filter((key) => hasModule({modules}, key));

  return (
    <div className="flex-1 overflow-y-auto bg-zinc-50">
      <div className="max-w-xl mx-auto px-6 py-16">
        <div className="rounded-lg border border-zinc-200 bg-white p-6">
          <div className="flex items-center gap-2 mb-3">
            <Lock className="w-5 h-5 text-zinc-400" />
            <h1 className="text-lg font-semibold text-zinc-900">Nothing has been switched on yet</h1>
          </div>

          {isLoading ? (
            <p className="text-sm text-zinc-500">Checking what you can reach…</p>
          ) : failed ? (
            /* Honest about not knowing. `useMyModules` fails OPEN so the menu
               does not vanish on a blip, which means arriving here after a
               failed check is possible — and saying "you have no access"
               would be a guess presented as a fact. */
            <p className="text-sm text-zinc-600">
              We could not check your access just now. Try reloading the page — your access has probably not changed.
            </p>
          ) : granted.length > 0 ? (
            <p className="text-sm text-zinc-600">
              You can reach {granted.map((key) => MODULE_LABELS[key]).join(', ')}, but not this part of the product.
              Use the menu to go somewhere you can.
            </p>
          ) : (
            <>
              <p className="text-sm text-zinc-600">
                Your account is set up and you are signed in{user?.name ? ` as ${user.name}` : ''}, but none of the
                three parts of the product have been turned on for you yet.
              </p>
              <p className="text-sm text-zinc-600 mt-3">
                Ask an admin on your account to open <span className="font-medium text-zinc-900">Manage users</span>,
                find your name, and tick the Intelligent Layer, Planner or Execution box — whichever you need.
              </p>
            </>
          )}

          <p className="mt-5 text-xs text-zinc-500">
            A new person starts with all three switched off, so this is expected rather than a fault.
          </p>
        </div>
      </div>
    </div>
  );
}
