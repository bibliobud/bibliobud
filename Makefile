# BiblioBud build / dev / api tooling.
#
# Most targets are thin wrappers over external tools. Install once:
#
#   npm i -g @redocly/cli                          # api-bundle, api-validate
#   go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest
#
# Phony all the things — this is a workflow Makefile, not a build system.

.PHONY: help api-bundle api-validate api-lint api-types docs-serve clean

help:
	@echo "BiblioBud Makefile"
	@echo ""
	@echo "API:"
	@echo "  api-bundle      Bundle split OpenAPI source into api/openapi.bundled.yaml"
	@echo "  api-validate    Lint the spec (redocly, strict rules)"
	@echo "  api-lint        Alias for api-validate"
	@echo "  api-types       Regenerate Go types from the bundled spec (smoke test)"
	@echo ""
	@echo "Docs:"
	@echo "  docs-serve      Serve docs/ locally (requires npx serve or python3 -m http.server)"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean           Remove generated artifacts"

api-bundle:
	@mkdir -p api
	npx --yes @redocly/cli@latest bundle api/openapi.yaml -o api/openapi.bundled.yaml

api-validate:
	npx --yes @redocly/cli@latest lint api/openapi.yaml

api-lint: api-validate

api-types: api-bundle
	@command -v oapi-codegen >/dev/null 2>&1 || { \
		echo "oapi-codegen not installed. Run: go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest"; \
		exit 1; \
	}
	@mkdir -p internal/httpapi/gen
	oapi-codegen -generate types -package gen -o internal/httpapi/gen/types.gen.go api/openapi.bundled.yaml
	@echo "Generated internal/httpapi/gen/types.gen.go"

docs-serve:
	@echo "Serving docs/ at http://localhost:8000"
	@cd docs && python3 -m http.server 8000

clean:
	rm -f api/openapi.bundled.yaml
	rm -rf internal/httpapi/gen
