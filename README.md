# Asset Library for Godot

A cache-first Godot editor asset browser with site adapters, portable creator/license
sidecars, GPU-compressed material preparation and generic source-file imports.
3D Texel is the first adapter. OpenGameArt, Poly Haven and ambientCG are not installed
as adapters yet.
Independent community addon, MIT. Godot 4.4+; tested on 4.4.1 and 4.7.2.
[Inspiration and attribution](ATTRIBUTION.md).

## Install and browse

Copy `addons/3dtexel/` into your project. Enable **Asset Library** in
**Project → Project Settings → Plugins**, then open the **Asset Library** editor tab.
After updating an installed addon, toggle it off/on to rebuild its controls.

- **Sites / keys** enables/disables providers and accepts masked session-only API keys.
  Environment keys still work. **All enabled sites** searches the combined local catalog;
  select a site to narrow it. No provider registration code belongs in the browser.
- **Search cache**, source/price/license filters, page changes and tile selection
  read local metadata only. An empty cache needs an explicit **Refresh**.
- **Refresh** fills/updates the current search's catalog, up to the service limit
  of 50 API pages / 2500 matches per source for Texel. That adapter uses sequential 50-record requests,
  paced to at most one API request per second per plugin instance. Click **Stop
  refresh** to stop after the current request, keeping what was cached.
- The **Per page** dropdown offers 12, 24, 48, 96, 192, 512 and 1024 locally.
- Thumbnails are stored on disk. A refresh authorizes missing thumbnails from its
  result set to load near the visible scroll area, with at most four active requests.
  Reopening the editor stays offline until another explicit refresh/download.
- **Refresh selected metadata** updates one asset and, when author/format information
  is missing, reads its public product page. Selecting a tile never does this itself.
- **Free only** is independent of **Any license**. Exact reported license names become
  filter choices as metadata is cached. Free non-CC0 materials are supported; unknown
  license fields remain unknown. Paid assets are browse-only, including owned assets.

Shared catalog: `user://asset_browser/catalog/assets.json`. Texel transport/thumbnail
cache: `user://3dtexel_cache/` (preserved from earlier versions). No automatic expiration, background catalog polling,
account responses, API keys or signed download responses are stored. Restarting the
editor preserves the cache. Local completed imports also populate the catalog.
**Check connection** is a separate, explicit account request, not a background check.

## Download and prepare

Select a tile, then check one or more variant boxes above **Download and prepare**.
Texel variants are resolutions; other adapters can offer model/audio/image formats.
Reported available sizes are shown when known. When the service has not supplied
availability, 1K/2K/4K are clearly labeled requests, not confirmed offerings; use
**Refresh selected metadata** to look for format declarations. No download probes
are used to guess sizes. The provider can substitute a size: the result and receipt
state the requested size, returned label and actual image dimensions.

For Texel materials, each checked size is processed sequentially. Completed local versions are reused
without contacting the API or downloading maps again. Request→returned-size aliases
avoid repeating a substituted download. Imports retain original source maps and
prepare mipmapped BC3/S3TC `*_texture.res` files and `material.res`, with anisotropic
filtering and DirectX→OpenGL normal conversion. Height is retained with displacement
off by default; AO stays a separate material map. Existing completed sources are
preserved; their credits can be filled in from cached metadata.

All download calls carry `max_credits: 0`. No paid downloads or generation controls
are implemented. The addon needs no Python, C#, Terrain3D or external image tools.

## Authentication

Refresh/searching the public service needs no key. Downloads need a free account
and API key with download permission: https://3dtexel.com/api-keys/ . Put
**TEXEL_API_KEY** in the environment that launches Godot. `3DTEXEL_API_KEY` and
`TEXEL` are also recognized. Keep using your normal launcher, including
`mise run godot -- --editor`, when it inherits that environment.

The optional `python3 tools/launch_editor.py /path/to/project` normalizes a
digit-leading variable name for shells that discard it; Python is not required by
the addon. Keys are never saved in project settings, sidecars, cache or screenshots,
and are sent only to the official API origin, never a file/CDN host.

## Credits and release preparation

New imports write `provenance.json`, `asset.credits.json`, `material.res.credits.json`
and sidecars for prepared texture resources. They include author names/URLs when
supplied, source URL, original license details, attribution requirements/text,
resolution and hashes. Explicit API/product-page author declarations are used;
publishers are not assumed to be asset creators. Missing authors/license fields
are flagged for review rather than invented. License labels are not blanket
permissions: retain and review the actual license record for release.

**Write saved-scene credits** traverses the saved scene's resource dependencies,
deduplicates asset credits and writes `<scene>.tscn.credits.json` plus a readable
`.credits.md`. **Credits on scene save** is enabled by default and can be switched
off. Other importers can use the same per-resource `.credits.json` or folder
`asset.credits.json` convention. Existing third-party metadata is normalized where
possible; assets with missing sidecars are listed explicitly. This does not
retroactively recover missing authors for every old import.

Runtime/dynamically loaded assets need separate inclusion: a saved dependency scan
cannot see everything a script may spawn. Unsaved edits are not included. A manual
command is also available (addon must be installed in the target project):

```sh
godot --headless --path /path/to/project -s /path/to/this/repo/tools/collect_scene_credits.gd -- res://scenes/world/example.tscn
```

## Optional Terrain3D handoff

Check **Also send to Terrain imports** for the companion Terrain Auto Import watcher
used by scrappersDelight. It receives original maps, a complete manifest and credits;
it does not paint terrain. The updated companion preserves credit sidecars on all
prepared terrain material/texture variants. Earlier companion versions retain the
source manifest but need their own sidecar propagation support.

Download resolution and terrain packing resolution are separate. The companion's
current global output size controls the packed terrain textures; all layers in one
Terrain3D library must match. Use separate libraries/output roots for 1K/2K/4K trials.
A 4K download passed to a 1K terrain packer still produces a 1K terrain layer.

## Tests: no live API traffic

CI, cache/pagination/credits tests and screenshot previews are offline. Network
behavior is replaced with fixtures/mocks, including provider limits and failures.
Previews use existing local cache entries and never fill missing entries remotely.

```sh
godot --headless --path . -s tests/test_core.gd
godot --headless --path . -s tests/test_cache.gd
godot --headless --path . -s tests/test_credits.gd
```

The old live smoke is guarded by `TEXEL_ALLOW_LIVE_TESTS=1`; do not use it for normal
validation. Explicit user browsing/downloads are how the real cache gets populated.
API documentation: https://3dtexel.com/developers/ . HDRIs/models/generation are outside
this addon's current scope. Screenshots in docs illustrate earlier UI versions.

## Extend with more sites

See [provider contract](docs/PROVIDERS.md) and the ready-to-use
[Antigravity implementation prompt](docs/ANTIGRAVITY_PROMPT.md). The addon folder
name remains `3dtexel` for upgrade compatibility. Provider scripts are discovered
from `providers/*/provider.gd`; no browser fork or extra plugin is needed.

Four license workflow statuses supplement exact terms: permissive, unknown/review,
commercial with attribution, blocked for this project. Share-alike/GPL are review
cases, not blanket prohibitions. Paid downloads remain unsupported.

Generic file imports keep a credit sidecar beside every source file. Archives are
preserved intact; automatic extraction/model wrapping are not implemented yet.
