# BiblioBud documentation

Documentation for users, operators, integrators, and contributors.

## Getting started

- [Self-hosting](getting-started/self-hosting.md) — run BiblioBud in
  Docker, configuration via environment variables, first-user bootstrap.
- [Development](getting-started/development.md) — clone, build, run
  tests, regenerate the OpenAPI bundle.

## Architecture

How BiblioBud is structured. Read these to understand the system at a
level a contributor needs.

- [Overview](architecture/overview.md) — the design plan in a nutshell.
- [Authentication](architecture/auth.md) — pluggable auth providers
  (Firebase + local), session lifecycle, token transport.
- [Entitlements](architecture/entitlements.md) — plans, capabilities,
  the Stripe integration that's coming.
- [Storage](architecture/storage.md) — repository interface, SQLite vs
  Postgres tradeoffs.
- [Book metadata sourcing](architecture/book-metadata-sourcing.md) —
  the resolver chain, lazy fetching, negative cache, manual entries.
- [User data import](architecture/user-data-import.md) — the importer
  interface, supported sources, idempotency contract.

## API reference

How to talk to the BiblioBud API as a third-party client.

- [Overview](api/overview.md) — base URL, auth, content types, the rules
  that apply to every endpoint.
- [Authentication](api/authentication.md) — how to obtain, refresh, and
  revoke a session token.
- [Errors](api/errors.md) — RFC 7807, the full code catalog, and how to
  switch on `code` instead of `title`.
- [Pagination](api/pagination.md) — opaque cursors, why offset isn't
  supported.
- [Idempotency](api/idempotency.md) — the `Idempotency-Key` header on
  POSTs that create resources.
- [Rate limiting](api/rate-limiting.md) — per-principal token buckets,
  what 429 looks like.
- [Versioning](api/versioning.md) — the v1 stability promise, deprecation
  policy.
- [Examples](api/examples/) — copy-pasteable curl walkthroughs.
- [OpenAPI spec](../api/openapi.yaml) — the source of truth.

## Guides

Task-oriented walkthroughs for end users.

- [Importing from GoodReads](guides/importing-from-goodreads.md)
- [Importing from StoryGraph](guides/importing-from-storygraph.md)
- [Importing from LibraryThing](guides/importing-from-librarything.md)
- [Generic CSV format](guides/generic-csv-format.md)
- [Exporting your data](guides/exporting-your-data.md)
- [Building a third-party client](guides/third-party-clients.md) —
  AGPL exception explainer, recommended auth flow.

## Operations

For people running a BiblioBud instance.

- [Deployment](operations/deployment.md)
- [Backup and restore](operations/backup-restore.md)
- [Upgrading](operations/upgrading.md)

## Contributing

- [Code style](contributing/code-style.md)
- [Testing](contributing/testing.md)
- [API changes](contributing/api-changes.md) — how to evolve OpenAPI
  without breaking clients.
