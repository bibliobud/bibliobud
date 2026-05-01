# Storage

BiblioBud supports two databases through one repository interface:

- **SQLite** — default for self-host. Zero configuration. The whole
  database is one file inside the container.
- **Postgres** — recommended for hosted. Concurrent writers, replication,
  point-in-time recovery, all the things you want for a SaaS.

The same Go code talks to both.

## Repository interface

```go
package storage

type Repository interface {
    Users() UserRepo
    Sessions() SessionRepo
    Books() BookRepo
    UserBooks() UserBookRepo
    Copies() CopyRepo
    Bookshelves() BookshelfRepo
    Tags() TagRepo
    Reviews() ReviewRepo
    Imports() ImportRepo
    Entitlements() EntitlementRepo

    // Transactional unit of work.
    InTx(ctx context.Context, fn func(Repository) error) error
}
```

Every service in `internal/<resource>/` accepts `Repository` and only
reads from `Repository` — services never know whether SQLite or
Postgres is behind the curtain.

The `InTx` method takes a callback that receives a `Repository` scoped
to a transaction. This way services can compose calls atomically without
leaking driver-level transaction APIs.

## SQLite vs Postgres tradeoffs

| Concern               | SQLite                           | Postgres |
|-----------------------|----------------------------------|----------|
| Concurrent writers    | Serial; WAL mode helps           | Native MVCC |
| Setup                 | One file                         | A whole service |
| Backups               | Copy the file                    | `pg_dump` or PITR |
| Full-text search      | FTS5 (built-in)                  | `tsvector` + GIN |
| JSON queries          | `json_extract`                   | `jsonb` operators |
| Replication           | Not really (litestream possible) | Streaming + logical |
| Cost at low scale     | Zero                             | Cheap but nonzero |
| Cost at high scale    | Falls over                       | Scales reasonably far |

Self-hosters get SQLite by default and can switch to Postgres by
setting `BIBLIOBUD_DATABASE_URL=postgres://…`. Hosted runs Postgres.

## Schema highlights

The full schema lives in migrations under `internal/storage/<driver>/migrations/`.
A few decisions worth calling out:

### `books` is global; `user_books` is the anchor

```
books (canonical, ISBN-keyed, shared across all users)
user_books (user_id, book_id) — anchor; status/rating/dates/notes
copies (id, user_id, book_id, …) — physical instances; 0..N per user-book
```

Lookups for "is this in my library?" hit `user_books` (constant-time
join). Lookups for "do I own this?" check for non-deleted `copies`
rows for the same `(user_id, book_id)`.

### Tags attach to the user-book pair

```
tags (id, user_id, name, …)
user_book_tags (user_id, book_id, tag_id)
```

A tag belongs to a user (no global namespace). Tag *assignments* live
on the `(user, book)` pair, not on the copy or the shelf — that's the
shape that makes the cross-cutting `/tags/{id}/books` view fast.

### Bookshelves reference books, not user-books

```
bookshelves (id, user_id, name, …)
bookshelf_items (bookshelf_id, book_id)
```

Adding a book to a shelf is independent of whether the user has read
it, owns a copy, or has any status set. Aspirational books shelve
fine. Adding a book to any shelf triggers an upsert of the user-book
anchor (so tags can be added later without surprise).

### Soft deletes

Most user-owned tables have a `deleted_at` column. Reads filter to
`deleted_at IS NULL`. A periodic GC job hard-deletes rows where
`deleted_at < now() - 30 days`.

Why 30 days: gives users a recovery window for accidental deletes and
matches the GDPR "right to be forgotten" without creating an undo
button on every UI surface.

### Negative cache

```
book_lookup_misses (isbn, last_attempted_at, providers_tried text[])
```

Used to short-circuit upstream provider calls for ISBNs nobody knows.
Entries older than 7 days are GC'd so transient provider outages
don't permanently poison lookups.

## Migrations

- `internal/storage/sqlite/migrations/`
- `internal/storage/postgres/migrations/`

Migrations are forward-only and applied at startup (with a flag to
disable for ops who want to migrate manually). Each migration is a
single SQL file numbered sequentially.

Both drivers share a logical schema but diverge in details (e.g.
`generated always as` columns work differently). Keep migrations
parallel — adding a column means writing two files, not one.

## What is NOT yet built

- **Connection pooling configuration knobs** for Postgres (defaults
  are sensible).
- **Read replicas** — the repository interface assumes a single
  database. Splitting reads is future work.
- **Sharding** — single-db scale is the v1 target.
