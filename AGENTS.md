# Asset Library

Independent Godot 4.4+ editor addon, MIT. Keep attribution in ATTRIBUTION.md.
Never store/log API keys, authorization headers, signed download URLs or account responses.
Read secrets only from the inherited environment. Default imports must not spend credits.
All network downloads use HTTPS. Native materials use GPU compression and mipmaps.
Keep source maps and provenance; do not overwrite completed imports.
Run `godot --headless --path . -s tests/test_core.gd` after changes.
Live tests are explicit opt-in, zero-credit CC0 downloads only.

Network policy: all automated tests and previews must be OFFLINE using mocks or existing cache. Do not hit the provider to validate limits or populate test data. Search submits a bounded site query; selection/page/filter changes reuse fetched metadata and images. Never sweep the whole site. Explicit user Search/update/download actions authorize network access; API calls are paced. Preserve author/license sidecars and mark unknown metadata rather than inventing credits.

Architecture: shared browser/core with directory-discovered provider adapters. Read docs/PROVIDERS.md before adding a site. Site endpoints belong only in providers/<id>/. Keep provider-qualified IDs, per-resource metadata, legacy Texel cache/import compatibility and offline provider-contract tests. Do not fork the browser for each site.
