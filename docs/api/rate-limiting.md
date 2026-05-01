# Rate limiting

BiblioBud applies per-principal token-bucket rate limits. The
defaults below apply to `bibliobud.com`; self-hosted instances can
tune limits via environment variables (or disable them entirely).

## How it works

- One bucket per principal (authenticated user) per route class.
- Unauthenticated requests share a per-IP bucket with much smaller
  capacity.
- Buckets refill continuously, not on a fixed window.
- `429 Too Many Requests` when the bucket is empty.

## Default limits (hosted)

| Route class                          | Capacity | Refill rate     |
|--------------------------------------|----------|-----------------|
| Reads (GET)                          | 120      | 60 / minute     |
| Writes (POST/PATCH/PUT/DELETE)       | 60       | 30 / minute     |
| `POST /books/refresh/{isbn}`         | 10       | 10 / day        |
| `POST /imports`                      | 5        | 5 / hour        |
| `POST /auth/login` (per IP)          | 10       | 5 / minute      |
| `POST /auth/password/reset/request`  | 3        | 3 / hour        |

The `metadata_refresh`, `large_imports`, and other capability gates
can lift specific quotas — see the entitlement on `/auth/me`.

## Response headers

Every response includes:

```
RateLimit-Limit:     60
RateLimit-Remaining: 47
RateLimit-Reset:     35
```

These follow the [IETF RateLimit Header Fields draft](https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/).
`RateLimit-Reset` is **seconds until the bucket has at least one
token again**, not a wall-clock timestamp.

## When you get a 429

```
HTTP/1.1 429 Too Many Requests
Retry-After: 12
RateLimit-Limit: 60
RateLimit-Remaining: 0
RateLimit-Reset: 12
Content-Type: application/problem+json

{
  "type": "https://bibliobud.com/errors/rate-limit-exceeded",
  "title": "Rate limit exceeded",
  "status": 429,
  "code": "rate_limit.exceeded",
  "detail": "Try again in 12 seconds."
}
```

- Honor `Retry-After` (in seconds). It's not a suggestion.
- Add jitter — if every client retries at exactly `Retry-After`, you
  get a thundering herd.
- Don't tighten your retry loop in response to a 429. Back off.

## Recommended client behavior

- Pace yourself off `RateLimit-Remaining`. If you see it dropping
  fast, slow down before you hit zero.
- Use `Idempotency-Key` so retries are safe (see
  [idempotency.md](idempotency.md)).
- For batch jobs (large imports, bulk migrations), pre-stage the
  work and process serially with `RateLimit-Reset`-aware backoff
  rather than firing parallel requests.

## Self-host configuration

```
BIBLIOBUD_RATELIMIT_ENABLED=true
BIBLIOBUD_RATELIMIT_READ_RPS=1
BIBLIOBUD_RATELIMIT_READ_BURST=120
BIBLIOBUD_RATELIMIT_WRITE_RPS=0.5
BIBLIOBUD_RATELIMIT_WRITE_BURST=60
```

Set `BIBLIOBUD_RATELIMIT_ENABLED=false` to disable entirely. This is
fine for personal-use single-user instances; not recommended for any
instance reachable from the public internet.
