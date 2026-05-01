# Generic CSV format

If you're migrating from a tool BiblioBud doesn't have a dedicated
importer for — or if you're hand-rolling a list — use the **generic
CSV** format. It's intentionally minimal: a small set of columns,
all with obvious semantics, all UTF-8.

## Required columns

| Column        | Type        | Notes |
|---------------|-------------|-------|
| `isbn`        | string      | ISBN-10 or ISBN-13. Hyphens optional. |

That's it. Every other column is optional and skipped if absent.

## Optional columns

| Column        | Type                                | Notes |
|---------------|-------------------------------------|-------|
| `title`       | string                              | Used as fallback if ISBN can't be resolved. |
| `author`      | string                              | Comma-separated for multiple authors. Fallback only. |
| `status`      | `wanted` \| `reading` \| `read` \| `dnf` \| empty | Empty leaves status null. |
| `rating`      | int 1..5 (or empty)                 | |
| `started_at`  | `YYYY-MM-DD`                        | |
| `finished_at` | `YYYY-MM-DD`                        | |
| `notes`       | string                              | |
| `shelves`     | string                              | Pipe (`\|`) separated list. Each becomes/joins a BiblioBud bookshelf. |
| `tags`        | string                              | Pipe-separated. Each becomes/joins a BiblioBud tag. |
| `owned`       | `true` \| `false` \| `1` \| `0`     | If truthy, creates a `Copy` row. |
| `format`      | `hardcover` \| `paperback` \| `ebook` \| `audiobook` \| `other` | Used on the created `Copy` only. |
| `condition`   | `new` \| `good` \| `fair` \| `poor` \| `unknown` | Used on the created `Copy` only. |

## Why pipes for `shelves` / `tags`?

Commas appear naturally inside shelf and tag names ("books I've
re-read, twice"). Pipes don't, and they sidestep CSV-escaping
ambiguity. Standard practice in CSV-as-API formats.

## Example

```csv
isbn,title,author,status,rating,started_at,finished_at,notes,shelves,tags,owned,format
9780441013593,Dune,Frank Herbert,read,5,2026-04-01,2026-04-29,"Holds up.",Sci-Fi|Hugo Winners,favorites|re-read,true,paperback
9780765326355,The Way of Kings,Brandon Sanderson,reading,,2026-04-15,,,Sci-Fi,doorstoppers,true,hardcover
9780062315007,The Alchemist,Paulo Coelho,wanted,,,,,Wishlist,,false,
0451524934,1984,George Orwell,read,4,,2024-09-12,"Re-read for book club",,classics|book-club,false,
```

## Encoding and dialect

- UTF-8 (no BOM, but BOM is tolerated).
- Comma-separated, double-quote escaping per RFC 4180.
- First line is the header. Column order doesn't matter — we look
  them up by name.
- Header lookup is case-insensitive and ignores spaces / underscores
  (`Date Read`, `date_read`, and `DateRead` all work — but the
  preferred form is the lowercase `snake_case` shown above).

## Upload

```bash
curl -X POST "https://example.com/api/v1/imports?source=generic" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -F "file=@my-library.csv"
```

`?source=generic` is required for this format — auto-detect
intentionally **does not** match generic CSV, because it would
swallow files we'd rather flag with a "we don't recognize this"
error.

## Re-imports

Idempotent. `user_books` upserts; shelf and tag membership
deduplicated; copies with `source=import` not duplicated.

## When to use this vs a real importer

If a dedicated importer exists for your source, use it — it knows
about source-specific quirks (StoryGraph's tag handling,
LibraryThing's collections, GoodReads' exclusive shelves) that the
generic format intentionally doesn't try to replicate.

Use generic CSV when:

- The original tool has no dedicated importer.
- You're constructing the file by hand or programmatically.
- You're round-tripping into a fresh BiblioBud instance and don't
  want to ship the source-specific export with it.

For round-trip backups, prefer the BiblioBud export format
(`source=bibliobud`) which preserves every field including IDs.
