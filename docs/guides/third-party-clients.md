# Building a third-party client

The BiblioBud REST API is a first-class public contract. Anyone is
free to build clients against it — browser extensions, mobile apps,
shell scripts, integrations with other tools.

## License — the AGPL exception

BiblioBud's server is AGPL-3.0. Software that **runs the server
code** (forks, hosted derivatives) inherits the AGPL.

Software that **only talks to the server over the documented HTTP
API** is **not** considered a derivative work and may use any
license — proprietary, MIT, GPL, anything. This carve-out is
explicit in the [project README](../../README.md).

In practical terms:

- A barcode-scanning iPhone app that calls `POST /copies` over HTTPS:
  any license you want.
- A browser extension that adds BiblioBud "Add to library" buttons
  to other sites: any license you want.
- A fork of the BiblioBud server with your own templates and
  business logic: AGPL-3.0.
- A "BiblioBud-compatible" server reimplementation that speaks the
  same API: any license you want (it doesn't include our code).

## Recommended auth flow

For interactive desktop / mobile apps:

1. Ask the user for their BiblioBud instance URL, then for their
   email and password (local mode) or trigger Firebase sign-in
   (firebase mode).
2. Call `POST /auth/login` (local) or `POST /auth/firebase/exchange`
   (firebase). Store the returned token in the platform credential
   store (Keychain / Keystore / DPAPI), **not** plain config.
3. Use the token via `Authorization: Bearer ...` on every request.
4. On 401 with `code: auth.session_expired` or `auth.session_revoked`,
   prompt the user to log in again.

For headless / batch tools:

1. Read the token from an environment variable
   (`BIBLIOBUD_TOKEN`) or a file in `~/.config/bibliobud/credentials`
   with mode 0600.
2. Document the expiry behavior — tokens last 30 days by default.

Personal access tokens (PATs) for unattended use are **not**
implemented in v1; the auth interface accommodates them and they're
on the roadmap.

## Detecting which mode an instance runs in

Hit one of the mode-specific endpoints — the wrong one returns 404
with `code: auth.signup_disabled` (in firebase mode) or its
firebase-specific equivalent (in local mode).

A more polite probe: an unauthenticated `GET /healthz` returns a
small JSON document that includes `auth_provider: "local" | "firebase"`.

## Code generation

The OpenAPI spec is the source of truth and is served at
`/api/v1/openapi.yaml` on every instance. Use any OpenAPI 3.0.3 code
generator — we test against `oapi-codegen` (Go) and
`openapi-typescript` (TS); other generators should work but aren't
in CI.

```bash
# Pull the spec from a live instance
curl -o bibliobud.openapi.yaml \
  https://example.com/api/v1/openapi.yaml

# Or grab the bundled spec from the repo
curl -o bibliobud.openapi.yaml \
  https://raw.githubusercontent.com/bibliobud/bibliobud/main/api/openapi.bundled.yaml
```

## Required client behavior

To be a well-behaved BiblioBud client, you should:

- **Set a `User-Agent`** identifying your client and version
  (`MyApp/1.4.0 (+https://example.com/myapp)`). Helps server
  operators correlate behavior to clients.
- **Honor `Retry-After` on 429.** Add jitter.
- **Switch on `code`, not `title`.** See
  [api/errors.md](../api/errors.md).
- **Send `Idempotency-Key` on creates.** See
  [api/idempotency.md](../api/idempotency.md).
- **Tolerate unknown response fields.** New fields are added in
  `v1` without notice.
- **Pin the API version prefix** (`/api/v1/...`). Don't follow
  redirects to `/api/v2` automatically — check release notes,
  test, then update.

## Things you may not do (hosted)

bibliobud.com applies these on top of the contract:

- **No scraping.** The API is the supported access path. Don't try
  to parse HTML out of the HTMX UI; it's not stable.
- **No bulk metadata harvesting.** The `books` table is for
  caching what your users actually look at, not for cloning the
  catalog into another product. The provider rate limits exist
  for a reason; we'll match them.
- **Respect rate limits.** Repeated abuse triggers per-client API
  key revocation. (Once API keys exist; for now, per-user.)

These restrictions don't apply to self-hosted instances — that's
the operator's call.

## Getting help

- File issues against the API at the BiblioBud repo.
- Tag your client in our (eventual) clients directory if you'd
  like it listed.
