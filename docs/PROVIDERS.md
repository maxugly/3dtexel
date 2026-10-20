# Provider contract v1

For the implementation and maintenance workflow, read
[Adding and maintaining site providers](ADDING_PROVIDERS.md). This file is the
compact interface reference; the base script is the source of method signatures.

The editor displays **Asset Library**. The installation path `addons/3dtexel/`
and repository name stay unchanged for compatibility; this is one addon, not one
addon per website. Site protocol code belongs only in `providers/<site>/`.

## Responsibilities

- `browser.gd`: shared tiles, site scope, local filters, search/stop, variant choices,
  credential controls, native import controls. It knows no site endpoints.
- `core/search_session.gd`: bounded fresh site queries with on-demand additional pages.
- `core/download_inventory.gd`: receipt-backed local version indicators.
- `core/download_selection.gd`: per-card selection and version-filtered queues.
- `core/registry.gd`: discovers `providers/*/provider.gd` at startup, rejects duplicate
  IDs, applies enable flags, combines enabled providers' catalogs, routes operations.
- `core/provider.gd`: adapter interface. Extend this script; do not introduce global
  class names or autoloads. An optional external addon can call `register_provider()`.
- `core/catalog.gd`: persistent public JSON catalog, identity `provider_id:id`.
- `core/preparation.gd`: native PBR material preparation, completed-import reuse,
  hashes, original source maps, portable sidecars and optional Terrain handoff.
- `core/file_preparation.gd`: generic source-file downloads for models, audio, images
  and archives, with a sidecar next to each file. Archives remain intact; automatic
  archive extraction and model wrapping are not implemented. Add reviewed shared
  format handlers rather than site-specific import UIs when needed.
- `credits.gd`: shared resource/scene credits. Saved-scene traversal cannot discover
  runtime-generated resource paths; those need separate inclusion.
- `core/license_policy.gd`: four workflow states with reasons. This is project policy,
  not a substitute for the exact license or other rights checks.
- `providers/texel/`: only the Texel adapter, REST client, legacy response cache and
  public-page metadata parser. Root client/cache/metadata scripts are compatibility
  shims. Prior Texel catalog and import paths remain readable; no assets are moved.

## Adapter methods

See the signatures and defaults in `core/provider.gd` and the complete Texel example.

`descriptor()` returns stable lowercase identifier `id`, display `name`, public
`website`, `key_env` array (empty if no API key), and `capabilities`. Register no
services or timers in the constructor. Store session keys only in memory;
`api_key()` should prefer the session key then documented inherited environment vars.
`credential_status()` must describe availability without echoing any key.

`local_assets()` returns normalized existing metadata without network access.
`refresh_page(query, category, cursor)` returns `{items: [...], next_cursor: "..."}`
or `{error: "..."}`. Empty cursor starts; empty next_cursor completes. Cursor
translation, pagination limits, rate pacing and retry-after handling belong to the
adapter. The core fetches only enough batches for the requested page size and requests
additional pages as needed. A repeated cursor stops that provider. Do not claim unsupported query categories work. Skip categories
that your provider cannot supply; return an empty result without network calls.

`asset_details(asset)` returns normalized details, reusing prior responses/page
metadata where available. `refresh_asset(asset)` can explicitly update those details. `resolve_download(asset, variant)`
returns a transient plan. Every operation checks `network_allowed`; search submissions query the site; filtering, already-fetched pages and variant
rendering reuse existing metadata. Search responses must be fresh, while repeated
detail/image requests reuse cache. `refreshing` means bypass cached search responses during a submitted search. `can_download()` is an offline availability
check, not a network probe. `check_connection()` is explicit. Thumbnail downloading
must honor a cache plus authorization granted by an explicit search/details/download action;
keep lazy viewport loading, bounded concurrency and disk caching. `cancel_all()`
cancels outstanding requests when disabled/removed. No hidden catalog updates.

## Normalized asset

```json
{
  "provider_id": "example",
  "provider": "Example Site",
  "id": "opaque-string-id",
  "title": "Worn steel",
  "type": "material",
  "url": "https://example.org/asset/123",
  "thumbnail": "https://example.org/preview.png",
  "description": "Original description",
  "tags": ["steel"],
  "price": {"free": true},
  "authors": [{"name": "Actual creator", "url": "https://example.org/artist"}],
  "license": {"name": "CC-BY-4.0", "url": "https://creativecommons.org/licenses/by/4.0/", "attribution_required": true},
  "licenses": [],
  "selected_license": {"name": "CC-BY-4.0"},
  "attribution_text": "Creator's requested wording",
  "metadata_source_url": "https://example.org/asset/123",
  "source_metadata": {},
  "retrieved_utc": "2026-10-20T00:00:00",
  "variants": [{"id": "original", "label": "Original GLB", "confirmed": true, "kind": "files"}]
}
```

`type` uses `material`, `model`, `audio`, or `image`; query category `all` includes
all. IDs are opaque strings, not integers. Never infer creators from site owners or
uploaders without evidence. Preserve all contributor credits, source/license text,
license versions, alternatives versus cumulative requirements, modification notices,
and any per-file exceptions. Missing metadata stays missing and flagged. Preserve a
sanitized original public metadata snapshot. Never persist signed URLs, account
responses, secrets or authorization. No live fixture harvesting.

`variants(asset)` returns offline choices, whose IDs are safe lowercase slugs.
Only expose confirmed reported versions. Unknown availability returns an empty
array, never guessed 1K/2K/4K requests. Material options include `resolution: "2k"`;
model options can include `lod: "low"` and `triangles: 1200`. `filter_key` and
`filter_label` optionally express cross-asset version filters. IDs remain safe slugs.
Models/audio may have `original` or documented formats. Do not assign texture
resolutions to model options. Cards render version buttons and imported indicators;
always-visible card checkboxes feed a sequential queue filtered by version, with
a five-second default pause. No separate batch mode.

## Transient download plans

Material plan:

```json
{"kind":"material","asset":{},"variant":"2k","maps":{"albedo":"https://...","normal":"https://..."},"normal_format":"opengl","material_props":{}}
```

`asset` must contain the same provider/asset identity as the selected asset, with
fresh verified price/metadata. Map roles: albedo, normal, roughness, height, ao,
metallic. Core packs GPU-compressed mipmapped resources and preserves raw sources.

Generic source plan:

```json
{"kind":"files","asset":{},"variant":"original","files":[{"filename":"model.glb","url":"https://..."}]}
```

Plans and URLs live in memory only. `get_bytes(url, absolute_destination, byte_limit)`
returns `{}` on success or `{error: ...}` and writes the file; obey HTTPS, bounded
redirects/size limits, and never forward authorization to CDN/file hosts. Core checks
filenames before generic downloads, refuses executable/script types, and preserves
partial files rather than silently overwriting them. Multi-file model dependencies
must be included explicitly. The current generic handler applies one asset credit
record to all files; mixed-license extraction needs a shared per-file handler. Archives are retained with credits; extraction into a
usable scene needs a shared safe format handler, not undocumented manual steps.

## Credits and policy

Sidecars are the portable source of truth; `user://asset_browser/catalog/assets.json`
is a convenient index, not the only place credits live. Imports use provider-qualified
folders plus hashed opaque IDs, preventing collisions. Metadata follows materials,
textures, source files, terrain handoffs, and saved-scene reports. Preserve sidecars
when moving assets; embedded metadata support is future work.

Four enum values (two bits can represent them; JSON uses readable accompanying
reasons): `0 PERMISSIVE`, `1 UNKNOWN`, `2 ATTRIBUTION`, `3 BLOCKED`. Current conservative
policy recognizes exact CC0/public domain declarations and versioned CC-BY/OGA-BY.
Unknown licenses, GPL and share-alike terms require review; they are not automatically
"cannot sell." Noncommercial terms and unverified paid entitlement are blocked for
this commercial project. Alternative license selection must be explicit and recorded;
never erase all the alternatives. A permissive status is not proof that attribution
metadata is complete or that every possible right is cleared. Paid downloads are
not implemented. Default imports must never spend money or credits.

## Verification

Run the twelve scripts in `.github/workflows/test.yml`, using mocks only.
`tests/test_providers.gd` demonstrates a second provider with string IDs, namespace
collisions, disabled sites, nested secret stripping, persistence, generic file import,
sidecars and completed-import reuse. Do not run `test_live.gd` or hit real providers
as part of automated tests. New provider tests must override every network path.
