# Errors

Every error response from the BiblioBud API is RFC 7807
`application/problem+json` with a stable `code` extension. Clients
**must** switch on `code`, never on `title` or `detail` — those are
human-readable and may change.

## Shape

```json
{
  "type": "https://bibliobud.com/errors/entitlement-required",
  "title": "Entitlement required",
  "status": 402,
  "detail": "This endpoint requires the `analytics` capability.",
  "code": "entitlement.required",
  "capability": "analytics"
}
```

| Field        | Source                              | Meaning |
|--------------|-------------------------------------|---------|
| `type`       | RFC 7807                            | URI identifying the error class. Stable. |
| `title`      | RFC 7807                            | Short human summary. May change. |
| `status`     | RFC 7807                            | Mirror of HTTP status. |
| `detail`     | RFC 7807                            | Long-form human explanation. May change. |
| `code`       | BiblioBud extension                 | **The contract.** Stable, machine-readable. |
| `errors`     | BiblioBud extension (validation)    | Per-field problems for `validation.failed`. |
| Resource fields | BiblioBud extension              | E.g. `capability`, `retry_after_seconds`, `existing_id`. |

## Compatibility promise

- New `code` values may be added at any time. Clients should treat
  unknown codes as the generic class implied by the HTTP status.
- Existing `code` values are never removed or repurposed without a
  major version bump (`/api/v2`).
- New extension fields may be added at any time. Don't fail on unknown
  extensions.

## Code catalog

The full enum is the source of truth at
[`api/components/schemas/ErrorCodes.yaml`](../../api/components/schemas/ErrorCodes.yaml).
This page groups codes by domain with the typical HTTP status and a
remediation hint.

### Auth

| Code                            | HTTP | What it means / what to do |
|---------------------------------|------|----------------------------|
| `auth.required`                 | 401  | No session token presented. Acquire one via `/auth/login` or `/auth/firebase/exchange`. |
| `auth.invalid_credentials`      | 401  | Wrong password (or unknown email — we deliberately conflate). |
| `auth.session_expired`          | 401  | Token past `expires_at`. Re-authenticate. |
| `auth.session_revoked`          | 401  | Token explicitly revoked (logout, password reset). Re-authenticate. |
| `auth.forbidden`                | 403  | Authenticated, but not allowed to touch this resource. Almost always means cross-user access. |
| `auth.signup_disabled`          | 404  | `POST /auth/signup` called against a `firebase`-mode instance. |
| `auth.email_taken`              | 409  | Signup with an in-use email. |
| `auth.username_taken`           | 409  | Signup with an in-use username. |
| `auth.password_reset_invalid`   | 400  | Reset token is unknown, expired, or already consumed. |
| `auth.firebase_token_invalid`   | 401  | Firebase ID token failed verification. Have the client refresh. |

### Validation

| Code                       | HTTP | What it means / what to do |
|----------------------------|------|----------------------------|
| `validation.failed`        | 422  | Generic catch-all. Inspect the `errors` extension for per-field problems. |
| `validation.required`      | 422  | A required field was missing. |
| `validation.out_of_range`  | 422  | Numeric value outside allowed bounds (e.g. `rating` not in 1..5). |
| `validation.invalid_format`| 422  | Format-level violation (bad email, malformed ISBN, bad cursor). |
| `validation.too_long`      | 422  | String exceeds max length. |
| `validation.too_short`     | 422  | String shorter than min length. |

`validation.failed` responses include an `errors` array:

```json
{
  "code": "validation.failed",
  "errors": [
    { "field": "rating", "code": "validation.out_of_range", "message": "must be between 1 and 5" },
    { "field": "isbn",   "code": "validation.invalid_format", "message": "not a valid ISBN-13" }
  ]
}
```

### Resource lifecycle

| Code                  | HTTP | What it means / what to do |
|-----------------------|------|----------------------------|
| `resource.not_found`  | 404  | The resource never existed (or was hard-purged after 30 days). |
| `resource.gone`       | 410  | Soft-deleted. The row exists for ~30 days then becomes 404. |
| `resource.conflict`   | 409  | Generic state conflict (preconditions). |
| `resource.duplicate`  | 409  | A unique-constraint collision. See domain-specific codes below for nicer messages. |

### Books / metadata

| Code                         | HTTP | What it means / what to do |
|------------------------------|------|----------------------------|
| `book.isbn_invalid`          | 400  | Path parameter is not a valid ISBN-10 or ISBN-13. |
| `book.not_found`             | 404  | No provider knows this ISBN. The negative cache will short-circuit subsequent lookups for 24h. |
| `book.provider_unavailable`  | 503  | All configured metadata providers are unhealthy or rate-limited. Retry with backoff. |
| `book.refresh_unavailable`   | 503  | `POST /books/refresh/{isbn}` could not reach any provider. |

### Library / copies / shelves / tags

| Code                         | HTTP | What it means / what to do |
|------------------------------|------|----------------------------|
| `library.anchor_not_found`   | 404  | `GET /library/{isbn}` for a book the user has never touched. |
| `copy.not_found`             | 404  | Copy ID does not belong to the caller (we return 404, not 403, to avoid leaking IDs). |
| `bookshelf.name_taken`       | 409  | Shelf name already exists for this user. |
| `bookshelf.not_found`        | 404  | Shelf ID does not belong to the caller. |
| `tag.name_taken`             | 409  | Tag name already exists for this user. |
| `tag.not_found`              | 404  | Tag ID does not belong to the caller. |

### Reviews

| Code                     | HTTP | What it means / what to do |
|--------------------------|------|----------------------------|
| `review.already_exists`  | 409  | One review per `(user, book)`. Use `PATCH /reviews/{id}` to update. |
| `review.not_found`       | 404  | Review ID does not belong to the caller. |

### Imports

| Code                          | HTTP | What it means / what to do |
|-------------------------------|------|----------------------------|
| `import.source_unrecognized`  | 400  | Auto-detect could not match any known source above the confidence threshold. Retry with explicit `?source=`. |
| `import.file_too_large`       | 413  | Hosted free-tier file size cap (default 10MB). Capability `large_imports` lifts it. |
| `import.parse_failed`         | 400  | File is malformed at the parser level (invalid CSV, etc.). |
| `import.job_not_found`        | 404  | Job ID does not belong to the caller. |
| `import.job_not_cancellable`  | 409  | `DELETE /imports/{job_id}` on a job already terminal. |

### Entitlements

| Code                          | HTTP | What it means / what to do |
|-------------------------------|------|----------------------------|
| `entitlement.required`        | 402  | The user's plan does not grant a capability this endpoint requires. Inspect the `capability` extension. |
| `entitlement.quota_exceeded`  | 402  | Within-capability quota hit (e.g. `metadata_refresh` daily cap). Inspect `quota` and `reset_at` extensions. |

### Rate limiting

| Code                  | HTTP | What it means / what to do |
|-----------------------|------|----------------------------|
| `rate_limit.exceeded` | 429  | Per-principal token bucket empty. Honor `Retry-After` (seconds) and back off. |

### Idempotency

| Code                    | HTTP | What it means / what to do |
|-------------------------|------|----------------------------|
| `idempotency.key_reused`| 409  | Same `Idempotency-Key` used with a different request body within the 24h window. |

### Server

| Code                          | HTTP | What it means / what to do |
|-------------------------------|------|----------------------------|
| `server.internal`             | 500  | Unexpected internal error. Report with the `request_id` extension. |
| `server.unavailable`          | 503  | Server is up but degraded (maintenance, draining). |
| `server.dependency_unavailable`| 503 | A backing service (DB, Firebase, Stripe) is unreachable. |

## Switching on `code` — minimal example

```python
def handle_response(resp):
    if resp.ok:
        return resp.json()
    err = resp.json()
    code = err.get("code", "")
    if code == "entitlement.required":
        prompt_upgrade(err.get("capability"))
    elif code == "rate_limit.exceeded":
        sleep(int(resp.headers.get("Retry-After", "1")))
        return retry()
    elif code.startswith("auth."):
        force_reauth()
    else:
        log_error(code, err.get("detail"))
    raise APIError(code)
```

Branch on prefix (`auth.`, `validation.`) for fall-through behavior;
branch on the full code for specific UX.
