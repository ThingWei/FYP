# RentHub Auth0 persistence result

Date: 4 October 2026

## Root cause

The Windows Auth0 gateway previously kept `_accessToken`, `_refreshToken`, and
`_expiresAt` only in process memory. Closing Flutter destroyed those values, so
`HybridAuthRepository.restoreSession()` had no Auth0 credential to restore and
the user had to open Universal Login again.

Local MongoDB/JWT sessions were already persisted independently by
`SessionIdentity`; that implementation was preserved.

## Secure-storage design

The native gateway now uses `flutter_secure_storage` with keys that are separate
from the local JWT keys:

```text
renthub_auth0_session_provider
renthub_auth0_session_refresh_token
```

Only the Auth0 provider marker and refresh token survive a process restart. The
access token and its expiry remain in memory. This minimizes persistent token
data and ensures a newly started process obtains a current access token from
Auth0 rather than trusting a previously cached bearer token.

No Auth0 token is stored in SharedPreferences, a plain file, source code, or
Git.

## Restoration flow

```text
Flutter starts
  -> try existing local JWT restoration
  -> if no valid local session, read Auth0 secure-storage marker/token
  -> POST Auth0 /oauth/token with grant_type=refresh_token
  -> persist a rotated refresh token when Auth0 returns one
  -> set the new access token in SessionIdentity memory
  -> POST /api/v1/users/session
  -> restore the RentHub user and active role
```

The authorization request already includes `offline_access`. The Auth0 API must
also have **Allow Offline Access** enabled and the Native application must allow
the Refresh Token grant for Auth0 to issue a refresh token.

Android now shares this token/persistence implementation. Its platform-specific
transport opens Universal Login externally and receives
`com.weith.renthub://login-callback` through an Android intent filter instead of
using the Windows loopback `HttpServer`. See `AUTH0_ANDROID_RESULT.md` for the
Dashboard and device setup.

Concurrent access-token requests share one in-progress refresh operation, which
avoids duplicate refresh-token exchanges.

## Hybrid-mode behavior

`HybridAuthRepository` keeps the existing priority:

1. restore a valid local MongoDB/JWT session;
2. otherwise restore Auth0 from secure storage;
3. otherwise show the login screen.

Tests confirm that a valid local session does not call Auth0 and an Auth0
session is restored when no local JWT session exists. Local token keys and Auth0
token keys remain separate. Selecting or restoring a local session removes a
dormant native Auth0 refresh token so logging out locally cannot unexpectedly
restore an older Auth0 account. A successful Auth0 session likewise removes any
persisted local JWT credentials.

## Rotation, failure, and logout behavior

- If refresh succeeds without a new refresh token, the existing refresh token
  is retained.
- If Auth0 returns a rotated refresh token, it replaces the saved token.
- `invalid_grant`, HTTP 401, and HTTP 403 clear the Auth0 provider marker,
  in-memory tokens, and persisted refresh token.
- A temporary transport/server failure does not erase a potentially valid
  refresh token; a future app start or request can retry.
- A RentHub `/users/session` 401 or 403 also clears Auth0 persistence.
- Deliberate Auth0 logout clears Auth0 persistence and the RentHub session, so
  the next process start cannot silently restore the logged-out user.
- The gateway does not loop after an invalid refresh token because the token is
  deleted before control returns to the unauthenticated UI.

## Automated tests

`test/auth0_persistence_test.dart` verifies:

- an authorization-code login persists the refresh token;
- a newly constructed gateway restores the saved token after a simulated
  process restart;
- an access token is obtained with `grant_type=refresh_token`;
- refresh-token rotation is persisted;
- an unrotated token is retained;
- `invalid_grant` clears Auth0 credentials;
- a temporary Auth0 failure retains the refresh token for a later retry;
- logout prevents restoration by a new gateway instance;
- hybrid mode restores local JWT first;
- hybrid mode restores Auth0 when no local JWT exists.
- Android accepts the exact configured callback and ignores unrelated links;
- Android sends PKCE S256 parameters and exchanges the authorization code;
- Android rejects a callback whose OAuth state does not match.

The test uses a real loopback callback server and an in-memory secure-storage
backend. It does not contact the production Auth0 tenant.

Final automated verification:

- Auth0 persistence and Android deep-link tests: 10 passed;
- complete Flutter suite: 113 passed, 2 intentionally skipped;
- Flutter analyzer: no issues;
- Android debug APK build: succeeded;
- complete Express/API suite in isolated mock-auth/local-storage test mode:
  125 passed, 3 optional live E2E tests skipped;
- complete FastAPI suite: 31 passed with 2 third-party deprecation warnings.

## Windows restart E2E result

The automated Windows restart-style integration test passes. It constructs a
new gateway instance against the same secure-storage backend and successfully
restores the session using a rotated refresh token.

A real tenant/browser close-and-relaunch check still requires an interactive
RentHub user and must be performed locally after confirming the Auth0 settings
below:

1. Auth0 application type is **Native**.
2. The configured loopback callback is in **Allowed Callback URLs**.
3. The application allows the **Refresh Token** grant.
4. The RentHub API has **Allow Offline Access** enabled.
5. Refresh Token Rotation is enabled or the tenant intentionally uses reusable
   refresh tokens.
6. Start RentHub, use **Continue with Auth0**, close the entire app, and start it
   again. The second start should call `/users/session` and enter RentHub without
   opening the browser.

## Files changed

- `apps/renthub_flutter/lib/core/auth/auth0_gateway_native.dart`
- `apps/renthub_flutter/lib/modules/user/repositories/auth_repository.dart`
- `apps/renthub_flutter/test/auth0_persistence_test.dart`
- `docs/AUTH0_PERSISTENCE_RESULT.md`

Web Auth0 behavior, local JWT behavior, MongoDB architecture, Socket.IO,
blockchain, payments, and XGBoost pricing were not restructured.
