## Epic 7: Authentication — Login & Register

### Context

The journey map editor currently loads without any authentication gate. This epic introduces
a login and registration experience so that users have a persistent identity, their journey
maps are scoped to their account, and no unauthenticated visitor can access or mutate data.

The backend already provides `POST /auth/login` and `POST /auth/signup` endpoints that return
an `authToken` + `user_id`. This epic wires those endpoints into a front-end auth shell.

### Explicit non-goals for this phase

- OAuth / social login (Google, GitHub, etc.)
- Email verification flows
- Role-based access control beyond what the `role` field already stores
- Multi-tenant org switching

---

### US-AUTH-01 — Login page

**Story:** As a returning user, I want a clean login screen so that I can authenticate and
reach my journey maps without friction.

**UX Notes:**
- Full-screen centered card layout (matches the zinc/white design language already in the app).
- Brand mark ("E" monogram + "Emgram" wordmark) at the top of the card.
- Fields: **Email**, **Password** (with show/hide toggle).
- Primary CTA: **"Sign in"** button — full-width, disabled while request is in flight.
- Secondary link: **"Don't have an account? Create one"** → navigates to Register.
- Tertiary link: **"Forgot password?"** → reserved/greyed out for this phase.
- Inline field-level validation: empty required field shown on blur, not before.
- API error (invalid credentials) shown as a non-blocking banner above the form.
- On success: `authToken` stored in `localStorage`, user redirected to the Dashboard.

**Acceptance Criteria:**
- Submitting with empty fields surfaces inline errors without calling the API.
- A spinner replaces the button label while the request is in flight.
- A failed login shows "Invalid email or password." — never exposes which field was wrong.
- A successful login stores `authToken` and `user_id` in `localStorage` and redirects.
- Navigating to `/login` while already authenticated redirects straight to the Dashboard.

---

### US-AUTH-02 — Register page

**Story:** As a new user, I want a registration screen so that I can create an account and
start building journey maps immediately after signing up.

**UX Notes:**
- Same centered card layout as Login for visual consistency.
- Fields: **Full name**, **Email**, **Password**, **Confirm password**.
- Password strength hint (weak / fair / strong) shown below the password field.
- Confirm password field shows a checkmark inline once both fields match.
- Primary CTA: **"Create account"** — full-width.
- Secondary link: **"Already have an account? Sign in"** → navigates to Login.
- On success: same token storage + redirect to Dashboard as Login.

**Acceptance Criteria:**
- Name and email are required; both validated on blur.
- Password must be at least 8 characters; shorter input disables submission.
- Confirm password mismatch blocks submission with an inline message.
- Email already in use returns "An account with this email already exists." banner.
- Successful signup redirects to the Dashboard with a first-time welcome state visible.

---

### US-AUTH-03 — Auth token management and protected routing

**Story:** As a developer, I want a single auth context layer so that every page in the
app can check session state and API calls can attach the token without repeating logic.

**UX Notes:**
- Unauthenticated users hitting any protected route are redirected to `/login`.
- The redirect preserves the attempted destination so the user lands there after login.
- A top-level loading state ("Checking session…") prevents a flash of the login page
  for users who have a valid stored token.

**Acceptance Criteria:**
- `authToken` is read from `localStorage` on app mount and held in React context.
- All Xano API calls include `Authorization: Bearer {authToken}` header.
- A 401 response from any API call clears the token and redirects to `/login`.
- A `<ProtectedRoute>` wrapper gates the Dashboard and the Map Editor.
- Calling `/auth/me` on mount verifies the token is still valid before granting access.

---

### US-AUTH-04 — Sign out

**Story:** As a signed-in user, I want a clear sign-out option so that I can end my
session and hand the device to someone else without leaving my data accessible.

**UX Notes:**
- Avatar or user initials chip in the top-right of the Dashboard header.
- Clicking it opens a small dropdown: **"Signed in as {name}"** (non-interactive label),
  divider, **"Sign out"** (destructive style).
- Signing out clears `localStorage`, resets auth context, and lands on `/login`.

**Acceptance Criteria:**
- Sign-out is reachable from the Dashboard and from inside the Map Editor.
- Signing out clears both `authToken` and `user_id` from `localStorage`.
- After sign-out, the back button cannot navigate back to a protected page.

---

### Recommended implementation sequence

```
US-AUTH-03 (auth context + protected routing) →
US-AUTH-01 (login page) →
US-AUTH-02 (register page) →
US-AUTH-04 (sign out)
```

### Dependencies

- Backend `POST /auth/login` and `POST /auth/signup` are already live.
- Backend `GET /auth/me` must be available to validate tokens on mount.
- React Router (or equivalent) must be introduced to the app before routing stories can land.
- US-AUTH-03 is a prerequisite for all dashboard and editor work in Epic 8.
