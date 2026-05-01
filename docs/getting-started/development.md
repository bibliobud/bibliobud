# Development

> **Status: stub.** The Go server isn't built yet. This page covers
> what *is* live: the OpenAPI source tree, how to bundle and lint
> it, and how the docs work. It will grow as the implementation
> lands.

## Repo layout

```
api/                OpenAPI 3.0.3 source (split + bundleable).
docs/               User, operator, integrator, contributor docs.
Makefile            Workflow targets (api-bundle, api-validate, ...).
.redocly.yaml       Redocly bundle + lint config.
README.md           Project overview.
```

The Go server (`cmd/bibliobud/`, `internal/`) does not exist yet.
The first implementation phase will scaffold it against the
finished spec.

## Prerequisites

- Node.js (any LTS) — used via `npx` to run `@redocly/cli`.
- Go 1.22+ — once the server lands.
- (Optional) `oapi-codegen` for the type-generation smoke test:
  ```
  go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest
  ```

## Working on the OpenAPI spec

```bash
make api-validate     # redocly lint, strict rules from .redocly.yaml
make api-bundle       # writes api/openapi.bundled.yaml (gitignored)
make api-types        # bundle + generate Go types as a smoke test
```

See [`api/README.md`](../../api/README.md) and
[`contributing/api-changes.md`](../contributing/api-changes.md) for
the editing rules.

## Working on docs

Docs are plain Markdown — render with anything. To preview:

```bash
make docs-serve       # python3 -m http.server 8000 in docs/
```

Or use any Markdown previewer that handles relative links.

## What's coming

When the Go server lands, this page will cover:

- Go module layout, build, and run targets.
- Database migrations (sqlc + a migration tool TBD).
- Live-reload during development (Air or equivalent).
- Tailwind / Templ build pipeline for the HTMX UI.
- How to run the test suite, including integration tests against
  SQLite and PostgreSQL.
