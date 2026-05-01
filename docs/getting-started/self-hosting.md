# Self-hosting

> **Status: stub.** The server isn't built yet — this page describes
> the intended self-host story so contributors can build to it. It
> will be filled in with concrete commands as the binary lands.

BiblioBud self-hosts as a single Go binary or a single Docker image.
There are no required external services — SQLite is the default
storage backend and PostgreSQL is the production option. Auth runs
in `local` mode (built-in password store + DB-backed sessions); no
Firebase, Stripe, or other SaaS dependency.

## Intended quick-start

```bash
docker run -d \
  -p 8080:8080 \
  -v bibliobud-data:/var/lib/bibliobud \
  -e BIBLIOBUD_AUTH=local \
  -e BIBLIOBUD_BASE_URL=https://books.example.com \
  ghcr.io/bibliobud/bibliobud:latest
```

The first user to register becomes the instance admin. After that,
new signups follow the registration mode you've configured.

## Environment variables (planned)

| Var                              | Default                  | Notes |
|----------------------------------|--------------------------|-------|
| `BIBLIOBUD_AUTH`                 | `local`                  | `local` or `firebase`. Self-host should be `local`. |
| `BIBLIOBUD_DB_URL`               | `sqlite:///var/lib/bibliobud/bibliobud.db` | `sqlite://...` or `postgres://...`. |
| `BIBLIOBUD_BASE_URL`             | `http://localhost:8080`  | Public origin. Used for cookie scope, password-reset links, OpenAPI servers list. |
| `BIBLIOBUD_BOOK_PROVIDERS`       | `openlibrary`            | Comma-separated; left = first tried. |
| `BIBLIOBUD_ISBNDB_API_KEY`       | (unset)                  | Enables the `isbndb` provider. |
| `BIBLIOBUD_RATELIMIT_ENABLED`    | `true`                   | Set `false` for personal-use single-user instances. |
| `BIBLIOBUD_REGISTRATION`         | `open`                   | `open` / `invite` / `closed`. |
| `BIBLIOBUD_PURGE_AFTER_DAYS`     | `30`                     | Soft-delete grace period before hard purge. |
| `BIBLIOBUD_CORS_ORIGINS`         | (empty)                  | Comma-separated list of additional CORS origins. |

The full list will live in `docs/operations/deployment.md` once the
binary exists.

## What to expect on a self-host

- **Every feature is enabled.** The capability resolver returns
  `unlimited` unconditionally. There is no paid tier.
- **Single binary.** No supplementary daemons.
- **Same API.** The OpenAPI spec served at `/api/v1/openapi.yaml` is
  identical to bibliobud.com's, minus the firebase-mode-only auth
  endpoints.
