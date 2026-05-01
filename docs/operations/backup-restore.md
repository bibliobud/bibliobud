# Backup and restore

> **Status: stub.** Concrete commands will land alongside the server
> implementation. The shape below is the intended backup story.

## What needs backing up

A BiblioBud instance's state is the database plus the upload directory:

- **Database.** SQLite file or a PostgreSQL database. Holds users,
  sessions, library data, books cache, import jobs, entitlements.
- **Uploads.** Import files and (eventually) avatar / cover image
  uploads, under `BIBLIOBUD_DATA_DIR/uploads`. Currently small.

That's it. Everything is regeneratable from the database — book
covers re-fetch from providers, the OpenAPI spec is embedded in the
binary, etc.

## Backup recipes

### SQLite

```bash
sqlite3 /var/lib/bibliobud/bibliobud.db ".backup '/backups/bibliobud-$(date +%F).db'"
```

`.backup` is online-safe — no need to stop the server.

### PostgreSQL

```bash
pg_dump --format=custom --file=/backups/bibliobud-$(date +%F).dump "$BIBLIOBUD_DB_URL"
```

Compress and ship offsite. Standard PostgreSQL backup hygiene
applies.

## Restore

### SQLite

```bash
systemctl stop bibliobud
cp /backups/bibliobud-2026-04-30.db /var/lib/bibliobud/bibliobud.db
systemctl start bibliobud
```

### PostgreSQL

```bash
systemctl stop bibliobud
pg_restore --clean --if-exists --dbname="$BIBLIOBUD_DB_URL" \
  /backups/bibliobud-2026-04-30.dump
systemctl start bibliobud
```

## User-side data portability

Independent of operator backups, every user can take a full export
of *their own* data via `GET /users/me/export`. See
[guides/exporting-your-data.md](../guides/exporting-your-data.md).

This is GDPR data portability, not operator backup — it doesn't
include other users' data, system tables, or session state. Don't
rely on per-user exports as your operational backup strategy.
