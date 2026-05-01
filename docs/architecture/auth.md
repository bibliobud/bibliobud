# Authentication

BiblioBud supports two authentication backends:

- **`local`** (default for self-host) — email/username + bcrypt password,
  built into the binary, with email-based password reset.
- **`firebase`** (default for `bibliobud.com`) — clients log in with the
  Firebase SDK and exchange a Firebase ID token for a BiblioBud session.

Both backends terminate at the same `Principal` object and the same
opaque session token. Most of the codebase doesn't know which backend
is in use.

## Provider interface

```go
type AuthProvider interface {
    // Validate an external credential (e.g. a Firebase ID token).
    // Returns the external identity, which the session minter uses to
    // upsert a User row.
    ValidateExternal(ctx context.Context, credential string) (ExternalIdentity, error)
}

type LocalAuthProvider interface {
    AuthProvider
    Signup(ctx context.Context, email, username, password string) (User, error)
    Authenticate(ctx context.Context, identifier, password string) (User, error)
    RequestReset(ctx context.Context, email string) error
    ConsumeReset(ctx context.Context, token, newPassword string) error
}
```

The `firebase` impl returns `ErrUnsupported` for `LocalAuthProvider`
methods. The corresponding routes (`/auth/signup`, `/auth/login`,
`/auth/password/reset/*`) return 404 in firebase mode. Likewise
`/auth/firebase/exchange` returns 404 in local mode.

## Sessions

Sessions are server-side, opaque, and revocable. We do not use JWTs.

```
sessions
  token_hash          (sha256 of the actual token; never store the raw token)
  user_id
  expires_at
  last_seen_at        (updated lazily on each request, ~once per minute)
  created_at
  revoked_at
```

The token issued to the client is a high-entropy random string with a
short prefix (`bb_sk_live_…`). Session lookup hashes the presented
token and selects on `token_hash`. The raw token only ever lives in
the response body or the cookie value.

### Lifecycle

1. **Mint**: On signup, login, or firebase exchange, the server inserts
   a session row, sets the cookie, and returns the token in the JSON
   body.
2. **Validate**: Every request runs the auth middleware. It reads the
   token from the `Authorization: Bearer` header or the `bb_session`
   cookie, hashes it, looks up the session, checks `expires_at` and
   `revoked_at`, and attaches the `Principal` to the request context.
3. **Revoke**: `POST /auth/logout` sets `revoked_at`. The cookie is
   cleared with `Max-Age=0`. Once revoked, the session row is preserved
   for audit, but lookups fail with 401.
4. **Expire**: A periodic job hard-deletes sessions where `expires_at`
   passed more than 30 days ago.

### Why one token, two transports?

Browsers want a cookie (so HTMX requests work without JavaScript
juggling tokens). Third-party clients want a bearer header (so they
don't get tangled up in cookie semantics). Issuing two different
credential types for the same identity duplicates revocation logic
and creates surprising behavior. Issuing one opaque token usable as
either a cookie or a bearer header is simpler and equally secure when
the cookie is `HttpOnly; Secure; SameSite=Lax`.

## Local-mode flow (sequence)

```
client                             server                          db
  │                                  │                              │
  │ POST /auth/signup                │                              │
  │ {email, username, password}      │                              │
  │ ────────────────────────────────►│                              │
  │                                  │ bcrypt(password)             │
  │                                  │ insert users                 │
  │                                  │─────────────────────────────►│
  │                                  │ insert sessions              │
  │                                  │─────────────────────────────►│
  │                                  │                              │
  │ Set-Cookie: bb_session=...       │                              │
  │ 201 { token, expires_at, user }  │                              │
  │ ◄────────────────────────────────│                              │
  │                                  │                              │
  │ GET /api/v1/library              │                              │
  │ Authorization: Bearer ...        │                              │
  │ ────────────────────────────────►│ session lookup               │
  │                                  │─────────────────────────────►│
  │                                  │ ctx.Principal = user         │
  │                                  │                              │
```

## Firebase-mode flow (sequence)

```
client                  Firebase           BiblioBud server          db
  │                       │                   │                       │
  │ Firebase SDK login    │                   │                       │
  │ ─────────────────────►│                   │                       │
  │ ID token              │                   │                       │
  │ ◄─────────────────────│                   │                       │
  │                                           │                       │
  │ POST /auth/firebase/exchange              │                       │
  │ { id_token }                              │                       │
  │ ─────────────────────────────────────────►│ verify ID token       │
  │                                           │ via Firebase Admin    │
  │                                           │  (one network call)   │
  │                                           │                       │
  │                                           │ upsert users          │
  │                                           │ keyed on Firebase UID │
  │                                           │──────────────────────►│
  │                                           │ insert sessions       │
  │                                           │──────────────────────►│
  │ 200 { token, expires_at, user }           │                       │
  │ ◄─────────────────────────────────────────│                       │
  │                                           │                       │
  │ GET /api/v1/library                       │                       │
  │ Authorization: Bearer <bibliobud-token>   │                       │
  │ ─────────────────────────────────────────►│ session lookup        │
  │                                           │ (no Firebase call)    │
```

The key choice: after the initial exchange, Firebase is **not in the
hot path**. Every subsequent request hits our session table only.

## Threat model

- **Token theft via cookie**: cookies are `HttpOnly; Secure;
  SameSite=Lax`. XSS that exfils via JS is mitigated by HttpOnly;
  CSRF is mitigated by SameSite=Lax + the bearer-only requirement
  for cross-origin POSTs.
- **Token theft via DB**: tokens are hashed at rest. A DB dump exposes
  hashes; presenting a hash does not authenticate.
- **Phishing the password reset**: reset tokens are single-use and
  expire in 1 hour. Successful consumption revokes all existing sessions.
- **Brute-force login**: per-IP and per-account rate limit on `/auth/login`.
  After N failures the account is temporarily locked.
- **Session fixation**: A new session is minted on every successful
  authentication; we never elevate an unauthenticated session.

## What is NOT yet built

- **Personal access tokens** (long-lived, scoped, revocable separately
  from interactive sessions). The session interface is designed to
  accommodate a `kind` column for this.
- **OAuth providers other than Firebase** (GitHub, Google direct).
  Drop-in via `AuthProvider`.
- **MFA** for local mode.
