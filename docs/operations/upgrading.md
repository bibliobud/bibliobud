# Upgrading

> **Status: stub.** The upgrade story will be filled in once the
> first releases happen. The intent below sets contributor and
> operator expectations.

## Versioning model

BiblioBud follows semantic versioning at the release level. The
**API** version (`/api/v1`) is independent of the **release**
version — the URL prefix only bumps on intentional API contract
breaks. See [api/versioning.md](../api/versioning.md).

Within `v1` of the API, server releases are:

- **Patch** (`0.4.x`): bug fixes, security patches. Always
  back-compat.
- **Minor** (`0.x.0`): additive features, new endpoints, performance
  work. Always back-compat.
- **Major** (`x.0.0`): may include schema migrations that require
  downtime, removal of deprecated features after their Sunset date,
  or operational changes. Read the release notes.

## Intended upgrade flow

1. Read the release notes.
2. Take a backup (see
   [backup-restore.md](backup-restore.md)).
3. Pull the new image / build the new binary.
4. Stop the service.
5. Start the new version. Migrations run automatically on startup
   under a transaction; failed migrations roll back and the server
   refuses to start.
6. Verify with `GET /healthz` and `GET /readyz`.

A failed migration leaves the database on the previous schema —
roll back to the previous binary and report the failure.

## Downgrades

Within a minor version (e.g. `0.4.2` → `0.4.1`): supported.
Across minor versions: supported only if no migration ran.
Across major versions: not supported. Restore from backup.

## What this page will cover

- Per-major-version upgrade notes (none yet — there are no
  releases).
- A section on running the migration tool standalone for operators
  who want to see the SQL before applying it.
- Specific guidance for any migration with notable runtime cost
  (long index builds, table rewrites).
