# Idempotency

Network retries are inevitable. The `Idempotency-Key` header lets a
client safely retry a `POST` without risking duplicate side effects.

## When to use it

Send `Idempotency-Key` on every `POST` that creates a resource:

- `POST /copies`
- `POST /bookshelves`
- `POST /bookshelves/{id}/items`
- `POST /tags`
- `POST /reviews`
- `POST /imports`
- `POST /follows/{username}`

Idempotency is **not** required on `PUT` or `DELETE` (already
idempotent by HTTP semantics) or on `POST` endpoints that don't
create resources (`/auth/login`, `/auth/logout`, etc.). The header is
silently ignored there.

## How to use it

Generate a UUID (v4 recommended) per logical operation and send it
with every retry of that same operation:

```bash
KEY=$(uuidgen)

curl -X POST https://example.com/api/v1/copies \
  -H "Authorization: Bearer ..." \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $KEY" \
  -d '{ "isbn": "9780441013593", "condition": "good" }'
```

If the request succeeds, you're done. If the connection drops, the
server responds 5xx, or you otherwise can't tell whether it landed —
retry with the **same** `$KEY` and the **same** body.

## Server behavior

| Scenario                                          | Server response |
|---------------------------------------------------|-----------------|
| First request with this key                       | Process normally. Cache the response keyed by `(user_id, idempotency_key)`. |
| Same key + same body within 24h                   | Return the cached response (status, headers, body) byte-for-byte. The new request is **not** processed. |
| Same key + **different** body within 24h          | 409 with `code: idempotency.key_reused`. Pick a new key. |
| Same key after 24h                                | Treated as a new request. |
| No key                                            | Process normally. The endpoint is not idempotent — duplicate requests may create duplicate resources. |

Body comparison is over the canonicalized JSON (whitespace and key
order ignored).

## Window

24 hours from the first successful response. Long enough for any
reasonable retry loop, short enough to keep the storage bounded.

## Generating keys

- **One key per logical operation**, not per HTTP attempt. Generate
  before the first attempt; reuse on every retry.
- UUID v4 is the easy choice. Anything globally unique works (ULIDs,
  KSUIDs, hashes of the request body + a timestamp).
- Keys are scoped per user, so collisions across users are
  irrelevant.
- Keys must be 1..255 ASCII characters.

## Interaction with rate limiting

A cached idempotent response **does not** consume a rate-limit token —
the server recognizes it and short-circuits before the bucket check.

## Things that are NOT covered

- `Idempotency-Key` does not retry the request for you. It makes
  retrying safe; the retry loop is your responsibility.
- It does not deduplicate across users. A leaked key from another
  user just creates a new resource for the caller.
- It does not protect against the server processing the request twice
  in flight (same key, two concurrent requests). The second request
  blocks until the first finishes, then receives the cached response.
