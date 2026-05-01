# Versioning

The BiblioBud HTTP API is versioned by URL prefix. The current
version is `v1`.

```
https://bibliobud.com/api/v1/...
```

## What v1 promises

While `v1` is in effect, these are **non-breaking** and may happen at
any time:

- Adding new endpoints.
- Adding new optional request fields, query parameters, or headers.
- Adding new response fields (clients must ignore unknown fields).
- Adding new schemas under `components/`.
- Adding new error `code` values (clients must treat unknown codes
  as the generic class implied by the HTTP status).
- Adding new tags, examples, or documentation.
- Adding new enum values to **request** schemas (clients should send
  values the server understands, so this only narrows what's
  rejected).
- Tightening server-side validation in ways that previously well-formed
  requests still pass (e.g. trimming trailing whitespace).
- Reordering response fields. JSON object key order is not significant.

These are **breaking** and would require a `v2`:

- Removing or renaming an endpoint, schema, field, header, or `code`.
- Changing the meaning or type of an existing field.
- Adding a new required request field.
- Removing an enum value from a **response** schema.
- Tightening validation such that previously accepted requests are
  now rejected (without a deprecation period).
- Changing the auth model or session token format.

## Deprecation policy

When something in `v1` is going to disappear in a future major version:

1. The OpenAPI spec marks it `deprecated: true`.
2. The endpoint or field continues to work unchanged.
3. Responses include a `Deprecation: true` header and a `Sunset:
   <RFC 7231 date>` header naming the removal date.
4. The release notes call it out under "Deprecated".
5. We give at least **6 months** between deprecation and removal in
   `v2`.

Clients should log warnings on any response with a `Deprecation`
header and migrate before the `Sunset` date.

## How `v1` and `v2` will coexist

When `v2` ships:

- `v1` continues to be served from the same binary for at least
  **12 months** after `v2`'s GA.
- `v1` and `v2` share the same database — they're different views,
  not different services.
- The "latest stable" version is whatever the docs at
  `bibliobud.com/docs` point at; the OpenAPI spec served at
  `/api/v1/openapi.yaml` always describes `v1` specifically.

## OpenAPI version vs API version

- `openapi: 3.0.3` is the spec format.
- `info.version` (e.g. `0.4.1`) tracks the **spec document** version
  and bumps every time we change the schema (semver: patch for fixes,
  minor for additive changes, major for breaks — but breaks shouldn't
  happen within a `v1`).
- The URL-prefix version (`/v1`) bumps only on intentional contract
  breaks. The two will not move in lockstep.

## Pre-1.0 caveat

Until BiblioBud reaches a 1.0.0 server release, the v1 API contract is
considered "stabilizing." We will avoid breaking changes, but reserve
the right to ship one with at least 30 days notice and a clear
migration path. Hosted deployments will not break clients without
warning.

After 1.0.0, the rules above are the rules.
