# Authentication

How third-party clients obtain, use, and revoke a BiblioBud session.

For the architecture-side view (provider interface, threat model,
internals), see [architecture/auth.md](../architecture/auth.md).

## Two modes, one client surface

A BiblioBud instance runs in either `local` mode or `firebase` mode.
Most third-party clients only need to support local mode (the
self-hosted case). If you target `bibliobud.com`, you also need
firebase-mode support, which means embedding the Firebase Web SDK
to acquire an ID token before exchanging it.

You can detect which mode an instance is in by inspecting an error:
`POST /auth/login` returns 404 in firebase mode,
`POST /auth/firebase/exchange` returns 404 in local mode.

## Acquiring a session

### Local mode

```bash
curl -X POST https://example.com/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{
    "identifier": "alice@example.com",
    "password": "correct horse battery staple"
  }'
```

Response (200):

```json
{
  "token": "bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d",
  "expires_at": "2026-05-30T15:32:18Z",
  "user": {
    "id": "...",
    "username": "alice",
    "email": "alice@example.com"
  }
}
```

The same endpoint also sets the `bb_session` cookie. Browser-based
clients can ignore the body and rely on the cookie.

### Firebase mode

1. Have your client log in with Firebase Auth and obtain an ID token.
2. Exchange it:

```bash
curl -X POST https://bibliobud.com/api/v1/auth/firebase/exchange \
  -H 'Content-Type: application/json' \
  -d '{ "id_token": "<firebase-id-token>" }'
```

The response is identical to local mode — opaque token + cookie.

After the exchange, the BiblioBud session is what authenticates
subsequent requests. **You do not need to refresh the Firebase token
or re-exchange.** Just use the BiblioBud token until it expires, then
exchange again.

## Using a session

Either header or cookie works:

```bash
# Header
curl https://example.com/api/v1/library \
  -H 'Authorization: Bearer bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d'

# Cookie (browsers handle this automatically; CLI tools rarely need it)
curl https://example.com/api/v1/library \
  -H 'Cookie: bb_session=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d'
```

Mix-and-match is fine. If both are sent, the bearer header wins.

## Inspecting the current session

```bash
curl https://example.com/api/v1/auth/me \
  -H 'Authorization: Bearer ...'
```

Response:

```json
{
  "user": { "id": "...", "username": "alice", "email": "alice@example.com" },
  "plan": {
    "plan": "pro",
    "status": "active",
    "valid_until": null,
    "capabilities": ["analytics", "metadata_refresh", "large_imports"]
  }
}
```

Clients should call this once after login and cache the result for the
session. Use `capabilities` to decide what UI to show; rely on 402
errors as the actual contract.

## Revoking a session

```bash
curl -X POST https://example.com/api/v1/auth/logout \
  -H 'Authorization: Bearer ...'
```

Returns 204. The session is revoked; the cookie is cleared if present.
Subsequent requests with the old token return 401 with
`code: auth.session_revoked`.

## Signup (local mode only)

```bash
curl -X POST https://example.com/api/v1/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{
    "email": "bob@example.com",
    "username": "bob",
    "password": "correct horse battery staple",
    "display_name": "Bob"
  }'
```

Returns 201 + a session, ready to use immediately.

## Password reset (local mode only)

Two-step flow. Both endpoints always return 204 to avoid leaking
account existence.

```bash
# Step 1: request reset email
curl -X POST https://example.com/api/v1/auth/password/reset/request \
  -H 'Content-Type: application/json' \
  -d '{ "email": "alice@example.com" }'

# Step 2: consume the token from the email
curl -X POST https://example.com/api/v1/auth/password/reset/confirm \
  -H 'Content-Type: application/json' \
  -d '{
    "token": "<from-email>",
    "new_password": "new password"
  }'
```

Successful reset revokes all existing sessions; the user must log in
again afterwards.

## Token storage recommendations

- **Browsers**: Use the cookie. The server sets it `HttpOnly; Secure;
  SameSite=Lax`. JavaScript can't read it, which is the point.
- **Native apps**: Use the bearer token. Store it in the platform's
  secure credential store (Keychain on iOS/macOS, Keystore on Android,
  DPAPI on Windows). Don't put it in plain config files.
- **CLI tools**: Bearer token in `~/.config/bibliobud/credentials`
  with mode `0600`. Or read from an env var. Don't bake into source.
- **Browser extensions**: Use the cookie if same-origin; bearer if
  cross-origin (be mindful of CORS).

## Rotation

There is no automatic token rotation in v1. Tokens last until their
`expires_at` (default: 30 days), at which point clients must
re-authenticate.

To force rotation, log out and log back in.

## Errors

| Status | code                             | When |
|--------|----------------------------------|------|
| 401    | `auth.required`                  | No token presented. |
| 401    | `auth.invalid_credentials`       | Wrong password. |
| 401    | `auth.session_expired`           | Token expired. |
| 401    | `auth.session_revoked`           | Token revoked (logout). |
| 401    | `auth.firebase_token_invalid`    | Firebase ID token failed verification. |
| 404    | `auth.signup_disabled`           | `/auth/signup` in firebase mode. |
| 409    | `auth.email_taken`               | Signup with an in-use email. |
| 409    | `auth.username_taken`            | Signup with an in-use username. |
| 429    | `rate_limit.exceeded`            | Too many failed login attempts. |

See [errors.md](errors.md) for the full catalog.
