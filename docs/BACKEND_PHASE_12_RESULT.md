# Backend Phase 12 Result — Auth0 and Real Uploads

## Delivered

- Auth0 Universal Login support for Flutter Web and Windows.
- Bearer access tokens on every authenticated REST request.
- The same verified Auth0 subject is used for Socket.IO sessions.
- Configurable namespaced Auth0 role, email, and display-name claims.
- Authorization Code + PKCE with state validation and a fixed loopback callback on Windows.
- Silent access-token renewal on Web and refresh-token renewal on Windows.
- Multipart uploads for listing images, avatars, identity documents, handover/return evidence, dispute evidence, and claim evidence.
- MongoDB upload metadata with SHA-256 checksums, ownership, purpose, visibility, MIME type, size, and storage path.
- File-signature checks for JPEG, PNG, WebP, and PDF instead of trusting the filename or request MIME type.
- Public content routes for listing/avatar images and authenticated private routes for identity/evidence files.
- Ownership and purpose checks before an uploaded reference can be attached to another record.
- Firebase Admin Storage for production and local disk storage for development/tests.
- Real file pickers in identity verification, Owner listing creation, handover, renter return, disputes/responses, and claims.

## API configuration

Copy `services/api/.env.example` to `services/api/.env` and provide real values outside source control:

```dotenv
NODE_ENV=production
AUTH_MODE=auth0
AUTH0_ISSUER_BASE_URL=https://YOUR_TENANT.auth0.com/
AUTH0_AUDIENCE=https://api.renthub.my
AUTH0_ROLES_CLAIM=https://renthub/roles
AUTH0_EMAIL_CLAIM=https://renthub/email
AUTH0_NAME_CLAIM=https://renthub/name
STORAGE_MODE=firebase
FIREBASE_STORAGE_BUCKET=YOUR_PROJECT.appspot.com
MAX_UPLOAD_BYTES=10485760
```

Firebase Admin uses Application Default Credentials. Set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account JSON file stored outside this repository, or use the workload identity supplied by the deployment platform.

## Auth0 Action

Add a post-login Auth0 Action that places the application roles and safe profile fields into the API access token. Assign `renter`, `owner`, or `admin` through Auth0 roles or `app_metadata.roles`.

```javascript
exports.onExecutePostLogin = async (event, api) => {
  const namespace = 'https://renthub';
  const roles = event.authorization?.roles ?? event.user.app_metadata?.roles ?? ['renter'];
  api.accessToken.setCustomClaim(`${namespace}/roles`, roles);
  api.accessToken.setCustomClaim(`${namespace}/email`, event.user.email);
  api.accessToken.setCustomClaim(`${namespace}/name`, event.user.name ?? event.user.email);
};
```

The API identifier in Auth0 must exactly match `AUTH0_AUDIENCE`. Use RS256 and register the client as a Single Page Application for Flutter Web.

## Flutter launch configuration

Web example:

```powershell
flutter run -d chrome --web-port 8080 `
  --dart-define=USE_MOCKS=false `
  --dart-define=API_BASE_URL=http://localhost:3000/api/v1 `
  --dart-define=SOCKET_URL=http://localhost:3000 `
  --dart-define=AUTH0_DOMAIN=YOUR_TENANT.auth0.com `
  --dart-define=AUTH0_CLIENT_ID=YOUR_CLIENT_ID `
  --dart-define=AUTH0_AUDIENCE=https://api.renthub.my `
  --dart-define=AUTH0_CALLBACK_URL=http://localhost:8080
```

Register `http://localhost:8080` as an Allowed Callback URL, Allowed Logout URL, and Allowed Web Origin.

For Windows, create an Auth0 Native application and use a fixed loopback callback:

```text
AUTH0_CALLBACK_URL=http://127.0.0.1:53124/callback
```

Register `http://127.0.0.1:53124/callback` as both an Allowed Callback URL and Allowed Logout URL. Enable refresh-token rotation for the Native application so the requested `offline_access` scope can renew API tokens. RentHub uses the system browser, validates OAuth state, and exchanges the authorization code with an S256 PKCE verifier; no client secret is embedded in Flutter.

If the Auth0 Dart defines are omitted while `USE_MOCKS=false`, RentHub deliberately keeps the existing development-header login so local MongoDB demonstrations remain usable.

## Validation

- API suite: 49/49 passed, including public/private upload access and file-signature rejection.
- Dart analyzer: clean.
- Focused live account/verification tests: 4/4 passed.
- Live Auth0-enabled Flutter Web build: passed.
- Auth0-enabled Windows debug build: passed.

Real Auth0 login and Firebase upload calls cannot be executed without the project tenant, client ID, API audience, bucket, and cloud credentials. No secrets or credential files were added to the repository.
