# Asset Library for Godot

One Godot editor browser with site adapters, creator/license sidecars and native
asset preparation. Independent community addon, MIT; Godot 4.4+ (tested on 4.4.1
and 4.7.2). [Inspiration and attribution](../../ATTRIBUTION.md).

**3D Texel is the first provider.** Other providers are added through the same
interface; OpenGameArt, Poly Haven and ambientCG adapters are not bundled yet.
The folder/repository name remains `3dtexel` for upgrade compatibility.

## Search and download

Copy `addons/3dtexel/` into your project. Enable **Asset Library** under
**Project → Project Settings → Plugins** and open the **Asset Library** tab.
Toggle the addon off/on after updating it to rebuild the controls.

- **Search** queries the selected sites. It fetches enough results for the requested
  page size, not every page of a search. **Next** requests more only when needed.
  Selecting a site or asset category submits a new search. Other filters reuse the
  returned results. Search responses contain whatever public metadata the site
  supplies; the browser does not make extra detail requests for every result.
- Metadata and thumbnails are retained on disk and reused automatically. There
  is no separate cache-search mode or offline toggle. Selecting a card does not
  redownload its files. Thumbnails load near the viewport, at most four at a time.
  The browser footer reports the combined on-disk cache size for every site.
  Clicking it asks for confirmation before clearing cached metadata and thumbnails;
  imported assets, receipts, and credits sidecars are left untouched.
- Each card shows **only confirmed download versions**, with a direct download
  button for each. Texture resolutions appear only for materials; model providers
  can supply LOD/format choices and triangle counts. Unknown sizes are never guessed.
  **Show versions** asks for details when availability has not been reported; repeated
  detail requests reuse stored metadata. No download probes discover available sizes.
- Imported versions display **✓**. Existing imports are discovered from their
  provenance and receipts, including old Texel imports. Reusing a completed import
  does not request or download the source again. Files are not silently overwritten.
- Card checkboxes are always visible. Missing available versions are selected by
  default; versions already imported are excluded. **Check all** toggles the cards
  on the displayed page. Opening more pages does not select unseen cards.
- **Download selected** queues only checked cards and versions allowed by the
  version filter. No filter means all missing versions. A **Resolution: 2K** filter
  queues only 2K; models without that choice do not enter that queue. Individual
  version buttons remain available regardless of the batch filter.
- Manually checking a fully imported card permits reusing those versions. A direct
  button marked ✓ also reuses local files. It does not force a destructive redownload.
- Downloads are sequential, with a configurable **five-second pause** between
  asset versions by default. No separate batch/experimental mode. **Stop** finishes
  the current operation and prevents subsequent downloads; it also interrupts the
  wait. The status line remains visible through searches, downloads and waits.
- **Free only**, exact license and license-status filters are separate controls.
  Free does not imply CC0. Paid downloads are unsupported and cannot spend credits.
- **Settings** contains site enable switches, website links, key controls, output
  folder, optional Terrain handoff and scene-credit controls. No extra download pane.

Per-page sizes: 12/24/48/96/192/512/1024. Large choices deliberately fetch more search
pages; provider limits still apply. Texel API requests are paced to one per second.
No automated tests or previews contact providers or scrape live fixture data.

## Authentication

Public Texel search needs no key; downloads require a free account/API key with
appropriate permissions: https://3dtexel.com/api-keys/ . Use an inherited
**3D_TEXEL_API_KEY**, **TEXEL_API_KEY**, **3DTEXEL_API_KEY**, or **TEXEL**, or enter a masked session-only
key under Settings. Session keys are never saved. Continue launching Godot normally,
including `mise run godot -- --editor` when it inherits your environment.

`tools/launch_editor.py` is an optional shell-environment workaround, not required.
Keys/account responses/signed download URLs are never written into project settings,
metadata, sidecars or screenshots. File/CDN requests never receive authorization.
All downloads use HTTPS; every Texel download request specifies `max_credits: 0`.

## Preparation and attribution

Native PBR materials retain original source maps and create mipmapped S3TC/BC3
textures with anisotropic filtering. DirectX normal maps have their green channel
converted for Godot. Height is retained with displacement off; AO stays a separate
map. Requested and actual returned sizes, image dimensions and hashes are recorded.
A provider substitution never marks an unreceived resolution as downloaded.

Generic model/audio/image/archive sources receive sidecars beside every file.
Archives are preserved intact; automatic extraction/model wrapping requires a shared
safe handler and is not implemented yet.

**Metadata travels with resources**, not just the local catalog. Imports write
`provenance.json`, folder `asset.credits.json` and per-resource `.credits.json`,
including source maps and derived textures/materials. Preserve those sidecars when
moving files. Records include reported creators, source/license URLs and terms,
attribution wording, sanitized public metadata, hashes, and selected license details.
Unknown creators/licenses remain flagged; uploaders/publishers are not invented as
creators. Existing missing metadata cannot always be recovered automatically.

Four workflow statuses accompany exact terms: permissive/no-credit-required,
unknown/review, commercial-with-attribution, blocked-for-this-project. Share-alike
and GPL terms need review, not blanket classification as prohibited or attribution-only.

**Credits on scene save** writes `<scene>.tscn.credits.json` and `.credits.md` from
saved resource dependencies. Settings also offers a manual scene-credit button.
Runtime-loaded assets require separate inclusion; unsaved edits are not scanned.

Optional **Also send materials to Terrain imports** passes original maps and credits
to the companion Terrain Auto Import watcher. The download resolution and that
watcher's output packing resolution are independent. Handoff does not paint terrain.

## Extension and verification

[Contributor guide: adding and maintaining site providers](docs/ADDING_PROVIDERS.md) ·
[Provider contract reference](docs/PROVIDERS.md).
Adapters are discovered in `providers/*/provider.gd`; the browser contains no site
endpoints. Catalog: `user://asset_browser/catalog/assets.json`; import index:
`user://asset_browser/imports/imports.json`; legacy Texel cache: `user://3dtexel_cache/`.
Portable sidecars remain the source of truth; indices can be rebuilt from imports.

Run the twelve offline scripts listed in `.github/workflows/test.yml`. Tests cover
search pacing/pagination, metadata and thumbnail reuse, real-only versions, card
selection, filters, completed imports, cross-site IDs, sidecars, download delays,
stop behavior, input and layout. `tests/preview.gd` must also stay offline.
