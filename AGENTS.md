# 3D Asset Library

Provider-neutral asset library, MIT. Keep attribution in `ATTRIBUTION.md`.
Two hosts share the same domain rules: the standalone Node app in `app/` and the Godot editor addon in `hosts/godot/`.

Never store/log API keys, authorization headers, signed download URLs, or account responses. Read secrets only from the inherited environment. Default imports must not spend credits.

## Standalone app (`app/`)

- Run `cd app && npm run check` after changes (source/test typecheck, offline tests, build).
- All automated tests and previews must be OFFLINE using mocks or checked-in fixtures. Do not hit a provider to validate limits or populate test data.
- Explicit user search/details/download/check actions authorize network access; API calls are paced. Search submits a bounded query; selection/page/filter changes reuse fetched metadata and images. Never sweep a whole site.
- Provider endpoints belong only in `app/src/providers/<id>/`. Keep provider-qualified IDs, per-resource metadata, and offline provider-contract tests.
- Only confirmed-free, zero-credit assets may be downloaded. Block NC/ND/proprietary/editorial/paid assets and mark unknown licenses for review.
- Preserve creator/license records and provenance sidecars; never invent credits.
- Keep source maps, declarations, and the reusable library/MCP/HTTP/CLI surfaces in sync.

## Godot host (`hosts/godot/`)

- Keep the original editor addon behavior under `hosts/godot/`.
- Run `godot --headless --path hosts/godot -s tests/test_core.gd` after Godot changes.
- Read `hosts/godot/docs/ADDING_PROVIDERS.md` and `hosts/godot/docs/PROVIDERS.md` before adding or updating a Godot provider.
- Keep provider-qualified IDs, per-resource metadata, legacy Texel cache/import compatibility, and offline provider-contract tests.
- Do not fork the shared browser for each site.
