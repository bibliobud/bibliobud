# Evolving the API

The BiblioBud public API is a contract. Third-party clients depend
on it. The rules below exist so we can keep growing it without
breaking those clients.

For the user-facing version of these rules, see
[api/versioning.md](../api/versioning.md). This page is for
contributors changing the spec.

## What's safe to ship in v1

| Change                                              | Safe? | Notes |
|-----------------------------------------------------|-------|-------|
| Add an endpoint                                     | yes   | |
| Add an optional request field                       | yes   | Default behavior must match "field absent". |
| Add a response field                                | yes   | Clients are expected to ignore unknown fields. |
| Add a new error `code`                              | yes   | Add to `ErrorCodes.yaml` enum + document in `docs/api/errors.md` in the same PR. |
| Add a new tag, example, or doc                      | yes   | |
| Add an enum value to a **request** schema           | yes   | Tightens the input space; doesn't change existing behavior. |
| Tighten validation that **was** rejected before     | yes   | If the reject reason changes, document the new code. |
| Loosen validation                                   | yes   | |
| Reorder fields in a response                        | yes   | Object key order isn't significant. |

## What's a breaking change (needs `v2`)

| Change                                              | Breaking? | Notes |
|-----------------------------------------------------|-----------|-------|
| Remove or rename an endpoint                        | yes       | |
| Remove or rename a response field                   | yes       | Add the new field, deprecate the old, ship removal in `v2`. |
| Change a field's type                               | yes       | |
| Add a new **required** request field                | yes       | Add it optional, deprecate sending without it, require in `v2`. |
| Remove an enum value from a **response** schema     | yes       | |
| Tighten validation such that previously **accepted** requests now fail | yes | Allow old form, deprecate, reject in `v2`. |
| Remove or repurpose an error `code`                 | yes       | |
| Change the auth model or token format               | yes       | |

## Workflow for an additive change

1. **Edit the spec.** Add the path, schema, parameter, or response
   under `api/`. Use `$ref`; don't inline schemas in path files.
2. **Bump `info.version`** in `api/openapi.yaml` (semver: minor for
   additive, patch for fixes).
3. **Run `make api-validate`.** Fix every error; review every
   warning.
4. **Run `make api-bundle`.** Make sure it builds. Don't commit
   `api/openapi.bundled.yaml` — it's gitignored.
5. **Update the docs.** New endpoint → add to relevant `docs/api/`
   page. New error code → catalog it in `docs/api/errors.md`. New
   capability-gated route → mention it in
   `docs/architecture/entitlements.md`.
6. **Add an example** under `docs/api/examples/` if the new shape
   is non-obvious. Examples should be valid against the schema —
   they're future integration test fixtures.
7. **Open a PR.** CI will run `redocly lint` and reject anything the
   bundler can't resolve.

## Workflow for a deprecation

When something must eventually go away:

1. Mark `deprecated: true` on the operation, parameter, or schema in
   the spec.
2. The server starts emitting `Deprecation: true` and `Sunset: <RFC
   7231 date>` headers on responses involving that endpoint or
   field. The Sunset date must be at least 6 months out.
3. Update `docs/api/versioning.md` and the affected doc page with a
   "Deprecated since vX.Y" callout and a migration recipe.
4. Mention it in release notes.
5. After the Sunset date passes, the removal goes into the next `v2`
   draft — never directly into `v1`.

## Adding a new error `code`

1. Add the code to `api/components/schemas/ErrorCodes.yaml`. Pick
   the namespace by domain (`auth.`, `book.`, `import.`,
   `entitlement.`, etc.).
2. Pick the HTTP status. Re-use one of the pre-baked
   `components/responses/Problem*.yaml` if possible; create a new
   `Problem<status>.yaml` if not.
3. Document the code in `docs/api/errors.md` with a one-line
   "what to do" hint.
4. If the response includes extension fields (e.g. `capability`,
   `quota`, `retry_after_seconds`), add them to the appropriate
   `Problem*.yaml` schema.

## Adding a new resource

1. Create `api/paths/<resource>.yaml` with the operations.
2. Create `api/components/schemas/<Resource>.yaml`.
3. Reference from `api/openapi.yaml` (every path needs a top-level
   `$ref`; the `~1` escaping is for `/`).
4. Add a `tags:` entry to `api/openapi.yaml` so docs render grouped.
5. Add a docs page under `docs/api/examples/<resource>.md`.
6. Add navigation entries in `docs/README.md`.

## Reviewing API PRs

Reviewers should ask:

- Does this break any v1 client? (See the table above.)
- Is `$ref` used for all schemas / responses / parameters?
- Are new error codes documented in **both** the enum and
  `docs/api/errors.md`?
- Is there an example covering the happy path?
- Does `make api-validate` pass with no new warnings?
- Does the operation ID follow `<resource><Verb>` and uniquely
  identify the route?

## When in doubt

If a change might be breaking and you're not sure, **make it
additive**. We can always deprecate the old form later. We can't
un-break a client.
