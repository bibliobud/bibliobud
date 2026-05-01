# Pagination

Every list endpoint in the BiblioBud API uses **opaque cursor
pagination**. Offset pagination is not supported and will not be added
in v1.

## Why not offset?

- Offset becomes incorrect under concurrent writes — a user inserting
  a row while you paginate causes you to either skip or duplicate
  results.
- Offset is `O(N)` on the database for late pages.
- Cursors let us change the underlying sort order without breaking
  clients (the cursor encodes its own sort key).

## Request

```
GET /api/v1/library?limit=50&cursor=eyJpZCI6IjAxSE5RTjVZMFowS01YIn0
```

| Param    | Type   | Default | Notes |
|----------|--------|---------|-------|
| `limit`  | int    | 25      | 1..100. Anything outside the range is clamped or returns `validation.out_of_range`. |
| `cursor` | string | absent  | Opaque token from a previous response. Omit on first page. |

The cursor is **opaque**. Do not parse it, do not assume it's
base64'd JSON (even though it currently is), do not generate one
yourself. Treat it as a string the server gave you to give back.

## Response

```json
{
  "data": [
    { "isbn_13": "9780441013593", "title": "Dune", ... },
    { "isbn_13": "9780765326355", "title": "The Way of Kings", ... }
  ],
  "next_cursor": "eyJpZCI6IjAxSE5SQzJZSE0wRDhKIn0",
  "total_estimate": 1247
}
```

| Field            | Type             | Notes |
|------------------|------------------|-------|
| `data`           | array            | The page of results. May be empty even when `next_cursor` is non-null (rare; tolerate it). |
| `next_cursor`    | string \| null   | Token for the next page. **`null` means you've reached the end.** |
| `total_estimate` | int \| null      | Approximate total. Skipped on collections where counting is expensive; clients should not rely on it for correctness. |

## Walking a collection

```python
cursor = None
while True:
    resp = get("/api/v1/library", params={"cursor": cursor, "limit": 100})
    for item in resp["data"]:
        process(item)
    cursor = resp["next_cursor"]
    if cursor is None:
        break
```

The loop terminates exactly when `next_cursor` is `null`. Don't try to
infer "last page" from `len(data) < limit` — the server is allowed to
return short pages.

## Cursor lifetime

Cursors are valid for **24 hours** after issue. After that the server
returns 400 with `code: validation.invalid_format`. In practice this
only matters for clients that paginate slowly and might pause
overnight; just restart from the first page.

A cursor is also invalidated if the underlying sort order changes
(extremely rare — would only happen on a major version bump).

## Filters and pagination

Filter parameters apply to the entire walk and are baked into the
cursor — you do **not** need to pass them again on subsequent pages,
and passing different filters with a non-empty cursor returns 400.

```
GET /api/v1/library?status=reading&limit=50            # first page
GET /api/v1/library?cursor=<token>&limit=50            # subsequent pages
```

## Stable ordering

Within a collection, the ordering is stable across the walk: a row
visible on page 1 will not reappear on page 5 (as long as it isn't
deleted and re-inserted between requests). Deletions during the walk
are silently absorbed; insertions during the walk may or may not
appear, depending on where they land relative to the cursor.

If you need a fully consistent snapshot, use the GDPR export endpoint
(`GET /users/me/export`) which returns everything atomically.
