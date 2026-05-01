# API overview

The BiblioBud JSON API is documented in OpenAPI 3.0.3. The source lives
in [`api/`](../api/) and is bundled to a single file at build time.
Every running instance also serves the spec at `/api/v1/openapi.yaml`.

This page summarizes the conventions that apply to every endpoint. The
per-resource pages and the OpenAPI document are the source of truth
for individual routes.

## Base URL

```
https://bibliobud.com/api/v1        # hosted
http://<your-host>/api/v1            # self-hosted
```

Breaking changes to the contract ship a new version prefix
(`/api/v2`). See [versioning.md](versioning.md) for the full policy.

## Content types

- Requests: `application/json` for most endpoints, `multipart/form-data`
  for `POST /imports`.
- Responses: `application/json` for success, `application/problem+json`
  for errors (RFC 7807). The OpenAPI types remain JSON schema either way.

## Authentication

One opaque session token, two transports:

```
Authorization: Bearer bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

or

```
Cookie: bb_session=bb_sk_live_zQ8v3y6F2nXk9pT4mLrB7uY1cAa5sH0d
```

Same token, same row in our session table. See
[authentication.md](authentication.md) for how to acquire one.

A small number of routes are unauthenticated (`/healthz`, `/readyz`,
`/openapi.yaml`, `/auth/signup`, `/auth/login`, `/auth/firebase/exchange`,
public `/users/{username}` profiles, public `/books/{isbn}/reviews`).
Everything else returns 401 without a session.

## Errors

Every error response follows RFC 7807 with a stable `code` extension:

```json
{
  "type": "https://bibliobud.com/errors/entitlement-required",
  "title": "Entitlement required",
  "status": 402,
  "code": "entitlement.required",
  "detail": "This endpoint requires the `analytics` capability.",
  "capability": "analytics"
}
```

**Switch on `code`, never on `title`.** `title` is for humans and may
change. `code` is the contract; new codes are additive, existing codes
are never repurposed without a major version bump. The full catalog
lives in [errors.md](errors.md).

## Pagination

Cursor-based:

```
GET /api/v1/library?limit=25&cursor=eyJpZCI6IjAxSE5RTjVZMFowS01YIn0
```

Response shape:

```json
{
  "data": [...],
  "next_cursor": "eyJpZCI6...",
  "total_estimate": 1247
}
```

When `next_cursor` is `null`, the client has reached the end. Cursors
are opaque — never parse them. Offset pagination is not supported. See
[pagination.md](pagination.md).

## Idempotency

`POST` endpoints that create resources accept an `Idempotency-Key`
header (UUID recommended). Retries with the same key + same body
return the same response. See [idempotency.md](idempotency.md).

## Rate limiting

Token-bucket limits per principal. Hits return 429 with `Retry-After`
and `code: rate_limit.exceeded`. See [rate-limiting.md](rate-limiting.md).

## Capability gating

Some endpoints require a capability the user's plan grants:

- 402 with `code: entitlement.required` and `capability: <name>` when
  the user lacks it.
- Self-hosted instances grant every capability — the gating is a
  no-op there.
- Clients should consult `/auth/me` for the user's `capabilities` array
  to decide what UI to show, but rely on 402s as the actual contract.

## Soft delete

`DELETE` endpoints return 204 and set `deleted_at`. For 30 days after
deletion, GETs return 410 Gone with `code: resource.gone`. After 30
days the row is hard-purged and GETs return 404.

## Timestamps

RFC 3339 UTC throughout. We never use locale-dependent date formats.

```
2026-04-30T15:32:18Z
```

`date` (no time) fields use `YYYY-MM-DD`.

## ISBNs

ISBN-13 is canonical. Endpoints that take an ISBN path parameter accept
both ISBN-10 and ISBN-13 — the server normalizes ISBN-10 to ISBN-13 and
both forms route to the same canonical Book row.

## CORS

Hosted: `bibliobud.com` and direct origins of registered third-party
clients. Self-host: configurable via `BIBLIOBUD_CORS_ORIGINS`.

## Compatibility promise

See [versioning.md](versioning.md). TL;DR:

- Adding endpoints, schemas, or fields: not a breaking change.
- Adding a new error `code`: not a breaking change.
- Renaming or removing endpoints, schemas, fields, or codes: requires
  a new version prefix.
- The `code` field is the stable contract — `title` text may change at
  any time.
