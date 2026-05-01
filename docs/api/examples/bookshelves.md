# Examples — Bookshelves

Bookshelves are 100% user-defined virtual buckets. There are no
system shelves — to-read / currently-reading / read live in
`user_books.status`, not in shelves. Shelf membership references
books directly, so aspirational books shelve fine without ownership.

```bash
TOKEN=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

## Create a shelf

```bash
curl -X POST https://example.com/api/v1/bookshelves \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{
    "name": "Sci-Fi",
    "description": "Anything with spaceships or strange physics."
  }'
```

```json
{
  "id": "01HQNS5XB7ZK0Q...",
  "name": "Sci-Fi",
  "description": "Anything with spaceships or strange physics.",
  "sort_order": 0,
  "items_count": 0,
  "created_at": "2026-04-30T16:01:42Z"
}
```

Shelf names must be unique per user. A duplicate returns 409 with
`code: bookshelf.name_taken`.

## List shelves

```bash
curl https://example.com/api/v1/bookshelves \
  -H "Authorization: Bearer $TOKEN"
```

Returns shelves with their item counts. Not paginated — even heavy
users rarely have hundreds of shelves.

## Add a book to a shelf

```bash
SHELF=01HQNS5XB7ZK0Q...

curl -X POST https://example.com/api/v1/bookshelves/$SHELF/items \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{ "isbn": "9780441013593" }'
```

Two side effects to know about:

1. The `books` row is resolved through the metadata provider chain
   if it isn't cached yet (lazy fetch).
2. The `user_books` anchor is upserted. The user doesn't have to
   `PUT /library/{isbn}` first.

## List items on a shelf

```bash
curl "https://example.com/api/v1/bookshelves/$SHELF/items?limit=50" \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "data": [
    {
      "isbn_13": "9780441013593",
      "book": { "title": "Dune", "authors": ["Frank Herbert"] },
      "added_at": "2026-04-30T16:02:01Z",
      "status": "read",
      "owned": true
    }
  ],
  "next_cursor": null
}
```

The status and `owned` fields are joined in from `user_books` and
`copies` — so a shelf view doubles as a filtered library view.

## Rename or reorder

```bash
curl -X PATCH https://example.com/api/v1/bookshelves/$SHELF \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Science Fiction",
    "sort_order": 2
  }'
```

## Remove a book from a shelf

```bash
curl -X DELETE https://example.com/api/v1/bookshelves/$SHELF/items/9780441013593 \
  -H "Authorization: Bearer $TOKEN"
```

Membership goes away. The `user_books` anchor, status, rating, tag
assignments, and copies all stay.

## Delete a shelf

```bash
curl -X DELETE https://example.com/api/v1/bookshelves/$SHELF \
  -H "Authorization: Bearer $TOKEN"
```

Soft-deletes the shelf. Books on the shelf are unaffected — they're
still in the user's library, still on any other shelves, still
tagged. Returns 204.

## Putting it together

A common end-to-end flow: import a CSV, then organize what came in.

```bash
# 1. Create a shelf for a project.
SHELF=$(curl -sX POST https://example.com/api/v1/bookshelves \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"name":"Hugo winners 2026","description":"To read this year"}' \
  | jq -r .id)

# 2. Add several books.
for ISBN in 9780441013593 9780765326355 9780385499231; do
  curl -sX POST https://example.com/api/v1/bookshelves/$SHELF/items \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -H "Idempotency-Key: $(uuidgen)" \
    -d "{\"isbn\":\"$ISBN\"}"
done

# 3. Cross-reference: of those, which haven't I read yet?
curl "https://example.com/api/v1/library?shelf=$SHELF&status=" \
  -H "Authorization: Bearer $TOKEN"
```
