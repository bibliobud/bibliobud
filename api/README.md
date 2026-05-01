# BiblioBud OpenAPI specification

The public BiblioBud HTTP API, defined in OpenAPI 3.0.3. The spec is
split across files for maintainability and bundled into a single
artifact for code generation and binary embedding.

## Layout

```
api/
  openapi.yaml                  Root document. Lists every path via $ref.
  paths/                        One file per resource group.
  components/
    schemas/                    Domain types (Book, UserBook, Copy, ...).
    parameters/                 Reusable query/path/header parameters.
    responses/                  Pre-baked RFC 7807 problem responses.
    securitySchemes/            bearer + cookie auth schemes.
  openapi.bundled.yaml          Generated. Single-file form with all $refs
                                inlined. This is what ships in the binary
                                and what code generators consume.
```

## Workflow

The split form is what humans edit; the bundled form is what tools consume.

```bash
# Bundle
make api-bundle           # writes api/openapi.bundled.yaml

# Validate + lint (uses .redocly.yaml)
make api-validate

# Regenerate Go types from the bundled spec
make api-types
```

## Conventions inside the spec

- **Inline schemas are forbidden in `paths/*.yaml`.** Use `$ref` into
  `components/schemas/`. Exceptions: ad-hoc request bodies and small
  inline response shapes that are obviously single-use.
- **Every error response MUST `$ref` `components/responses/Problem*.yaml`.**
  The stable contract is the `code` field, enumerated in
  `components/schemas/ErrorCodes.yaml`. Adding a new error code is a
  spec change — it goes in that enum first, then in the doc catalog at
  `docs/api/errors.md`.
- **No example data inside paths.** Examples live next to the schema
  they belong to, or under `docs/api/examples/`.
- **Operation IDs** follow `<resource><Verb>`: `booksGetByISBN`,
  `bookshelvesAddItem`, `tagsListBooks`. Code generators use these as
  function names.

## Why split + bundle

1. **Diffs stay readable.** Adding an endpoint touches one path file
   plus maybe one schema file, not a 2000-line yaml.
2. **Code generators want a single file.** `oapi-codegen` and most
   downstream consumers prefer fully-resolved specs.
3. **The binary embeds one file.** The server serves
   `GET /api/v1/openapi.yaml` from the embedded bundled artifact.

## Adding an endpoint — checklist

1. Add the operation to the appropriate `paths/<resource>.yaml` (create
   the file if a new resource group). Use `$ref` for every schema /
   parameter / response.
2. If a new schema is needed, create `components/schemas/<Name>.yaml`.
3. If a new error condition is possible, add a stable code to
   `components/schemas/ErrorCodes.yaml` AND document it in
   `docs/api/errors.md`.
4. Reference the new path in `openapi.yaml` under `paths:` with a JSON
   pointer (`/~1foo~1bar` is the escaped form of `/foo/bar`).
5. Run `make api-validate`. Fix every error; review every warning.
6. Add or update an example under `docs/api/examples/`.
