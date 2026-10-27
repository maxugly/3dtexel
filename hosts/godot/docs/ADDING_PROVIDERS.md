# Adding and maintaining site providers

Asset Library uses one shared editor interface and a separate adapter for each
website. Contributors add or repair a site's adapter without duplicating the
browser, downloader, import pipeline or attribution system. This guide applies to
human contributors and coding agents alike.

The addon lives at `addons/3dtexel/` for compatibility with existing installations.
A provider is a set of trusted GDScript files inside that addon, not another Godot
EditorPlugin. The current reference implementation is
[`providers/texel/`](../addons/3dtexel/providers/texel/).

The [provider contract](PROVIDERS.md) describes the data structures and method
signatures. The actual base class is
[`core/provider.gd`](../addons/3dtexel/core/provider.gd). Read both before writing
an adapter. This guide explains the development and maintenance workflow.

## The boundary that keeps updates small

A provider owns its site's URLs, API calls or permitted page parsing, pagination,
authentication, rate limits, cache validation and interpretation of source metadata.
It translates those details into the common asset and download-plan structures.

The core owns the search interface, site switches, card checkboxes, version buttons,
version filters, download queue, five-second default pause, status display, import
inventory, material preparation, source-file handling and credit sidecars. New site
code should not add branches such as `if provider == "example"` to those systems.

The normal flow is:

1. The user submits a search. The core asks enabled providers for bounded result pages.
2. A provider returns normalized asset summaries and a continuation cursor.
3. The core indexes public metadata and displays cards. Existing metadata and images
   are reused; more result pages are fetched only when needed.
4. When the user requests missing version information, the provider supplies details.
   Already fetched details are reused. Unknown availability is never guessed.
5. The user clicks a version button or downloads checked cards. The provider resolves
   a short-lived download plan for that exact asset and version.
6. The core fetches the files through the provider's transport, prepares supported
   resources, writes provenance and credit sidecars, and records the actual version
   imported. That import record drives the checkmarks on cards.

A site changing an endpoint or HTML layout should ordinarily affect only its
provider directory and tests. A genuinely new *file format* may need a shared
preparation handler; that is a separate change from adding another website.

## Before implementing a site

Identify its public search/detail/download mechanism and the terms governing that
access. Prefer documented APIs or feeds. Do not assume that a WordPress site,
public download page or browser-visible request implies a supported public API.

Record what the adapter can actually support: materials, models, audio or images;
search versus explicit asset lookup; authentication; available file formats;
creator/license fields; rate limits; and any missing metadata. If search cannot be
implemented through permitted access, document that gap rather than crawling the
site or claiming support. The current shared UI does not include a generic paste-URL
import flow; adding one would be a separate reusable core feature.

Decide which source IDs and version IDs are stable. An asset ID must identify the
same source asset even if its title changes. Version IDs must distinguish materially
different offerings, such as a model's low-detail GLB and high-detail FBX. Never use
a signed download URL, array position, translated display label or current search
rank as the asset identity.

Do not populate fixtures by sweeping the service. Automated tests and previews must
remain offline. Any small manual online verification should be explicitly authorized,
respect the site's access policies and avoid repeated downloads.

## Create the provider directory

Use a structure such as:

```text
addons/3dtexel/providers/example/
    provider.gd       # Extends core/provider.gd; implements the common interface
    client.gd         # Site transport, authentication, pacing and response cache
    parser.gd         # Pure source-data -> normalized-data functions, if needed
    README.md         # Supported features, limits and site-specific maintenance notes
    ATTRIBUTION.md    # Upstream code/license notices, if applicable

tests/providers/example/
    test_example.gd
    fixtures/         # Synthetic, sanitized JSON/HTML and tiny test files
```

Only `provider.gd` has a required name/location. Other files are implementation
choices. Keep parser code separate from HTTP where practical so site-layout fixes
can be tested without a network connection.

The registry discovers `providers/*/provider.gd` when the browser is constructed.
The script must extend the base provider and return a unique descriptor ID. No
registration change in the browser, second editor tab, extra plugin.cfg, autoload,
background daemon or global `class_name` is needed. Constructors must not start
network requests, timers or catalog synchronization.

Start from the base class and the Texel implementation. This minimal skeleton is
intentionally nonfunctional until its source parsing and transport are implemented:

```gdscript
@tool
extends "res://addons/3dtexel/core/provider.gd"

func descriptor() -> Dictionary:
    return {
        "id": "example",
        "name": "Example Site",
        "website": "https://example.org/",
        "key_env": [],
        "capabilities": ["model", "variants"]
    }

func refresh_page(_query: String, _category: String, _cursor: String) -> Dictionary:
    if not network_allowed:
        return {"error": "Search was not started."}
    return {"error": "Example site search is not implemented."}

func asset_details(_asset: Dictionary) -> Dictionary:
    if not network_allowed:
        return {"error": "Asset details were not requested."}
    return {"error": "Example site details are not implemented."}

func resolve_download(_asset: Dictionary, _variant: String) -> Dictionary:
    if not network_allowed:
        return {"error": "Download was not requested."}
    return {"error": "Example site downloads are not implemented."}
```

This appears under site settings after installation, but the base class deliberately
keeps `can_download()` false. Implement that offline availability check, real version
metadata, download resolution, transport and thumbnails before claiming the adapter
is usable. Descriptor capabilities are currently descriptive, not automatic feature
validation or a substitute for implementing the methods.

## Implement search and details

`refresh_page(query, category, cursor)` handles one bounded source page and returns
`{items: [...], next_cursor: "..."}`. An empty input cursor starts a search; an empty
output cursor ends it. Cursors are opaque to the core. Keep their interpretation in
the adapter; do not put credentials or signed URLs in them.

The shared categories are `all`, `material`, `model`, `audio` and `image`. Return an
empty completed page without a request when the site cannot supply a category.
Preserve the site's result order. Detect invalid/repeating pagination and return a
useful error instead of retrying indefinitely. The core also guards repeated cursors.

Search must query the source for current matches. Repeated detail lookups and images
should reuse their cached responses. Use conditional HTTP requests when the source
supports validators; do not assume it supports a lightweight IDs-only endpoint.
Avoid a second detail call for every result when the search response already provides
what the card needs. Keep richer cached authors, licenses and versions when a new
summary simply omits those fields. Explicit source changes must still be respected.

`asset_details(asset)` supplies missing details with reuse of existing data.
`refresh_asset(asset)` is available for an explicit metadata update; the current
browser uses `asset_details()` for its **Show versions** action. Neither method may
probe downloads to discover sizes. `local_assets()` and `local_import_roots()` are
optional ways to expose existing public metadata and discover legacy import receipts.

Return normalized dictionaries, not raw site records alone. The identity is the pair
`provider_id` and opaque string `id`; two sites may use the same ID safely. Include
public source URLs, title, type, price availability, actual authors, exact license
records, attribution wording and a sanitized source snapshot. The full example and
supported persisted fields are in [PROVIDERS.md](PROVIDERS.md).

The catalog intentionally keeps a limited set of normalized fields. Place additional
public source evidence inside `source_metadata`; adding arbitrary top-level fields
does not guarantee that they survive indexing or resource preparation.

## Expose real versions

`variants(asset)` must be fast and offline. Return only choices that the source
actually reports, each with a stable safe lowercase-slug `id`, `label` and
`confirmed: true`. Return an empty array when availability is unknown. The core does
not display speculative choices marked unconfirmed.

Material examples:

```json
[
  {"id":"2k", "label":"2K", "resolution":"2k", "confirmed":true},
  {"id":"4k", "label":"4K", "resolution":"4k", "confirmed":true}
]
```

Model examples:

```json
[
  {"id":"low-glb", "label":"Low · GLB", "lod":"low", "triangles":1200, "confirmed":true},
  {"id":"high-glb", "label":"High · GLB", "lod":"high", "triangles":4800, "confirmed":true}
]
```

Only materials use the shared resolution filter. Do not give models fictional 1K,
2K or 4K choices. `lod` groups model variants for filtering; `triangles` supplies a
reported count for the button tooltip. Counts not reported or measured must stay
absent. Use `filter_key` and `filter_label` when a source needs a meaningful shared
format/version filter, for example `format:glb`. Prefer descriptive labels to cryptic
letters unless their meaning is clear.

The core displays direct version buttons, imported checkmarks and always-visible
card checkboxes. Without a version filter, checked cards queue all missing versions.
A 2K filter queues only 2K. **Check all** affects displayed cards; unseen cards are
not silently selected. Explicitly selecting an existing version allows local reuse.
Adapters must not create a competing selection UI or independent batch downloader.

## Resolve downloads; let the core prepare them

`resolve_download(asset, variant)` returns a transient plan. It must preserve the
selected asset's provider/ID, verify that the requested choice exists and avoid
spending money or credits. `can_download()` alone is not final price/entitlement
verification. Respect source terms and error responses at resolution time.

Use a `material` plan for known PBR map roles, or a `files` plan for ordinary source
files. See the exact schemas in [PROVIDERS.md](PROVIDERS.md). Material plans can
state the normal-map convention, actual returned resolution and material properties.
File plans include every needed companion file under safe relative-free filenames.
Never invent a successful size substitution: record the version actually received.

Download URLs are short-lived plan data, not catalog or credit fields. Resolve them
near the download, not while searching. `get_bytes(url, absolute_destination, limit)`
writes the requested temporary file and returns a result/error dictionary. The core
handles publication, hashes, provenance, import receipts and supported preparation.

Current generic-file handling keeps archives intact. It does not extract them,
rewrite external glTF dependencies, wrap every model in a ready-to-place scene, or
handle every possible file extension. A site offering ZIPs is not automatically a
complete in-editor model workflow. Document that distinction. New safe extraction
or format conversion belongs in a shared preparation handler with separate tests.

## Keep creator and license evidence with the resource

This is a required behavior, not optional catalog decoration. Sidecars are portable;
the user-local catalog is a convenience index. Use the common credit schema and
preparation path so metadata accompanies original files, derived textures/materials,
Terrain handoffs and saved-scene reports.

Preserve declared authors and contributors, source/license URLs and versions,
required attribution text, notices, modification information, license alternatives
versus cumulative requirements, selected terms and file-specific exceptions. Keep
source evidence sanitized. Do not identify a site owner, publisher or uploader as
the creator unless the source actually establishes that relationship.

The four workflow states supplement the exact license records; adapters do not
replace the core policy. Unknown or ambiguous information stays under review.
Do not collapse mixed-license packs to one convenient license or select the least
restrictive-looking option without evidence that it is genuinely an alternative.

**Current limitation:** the generic `files` handler writes one asset credit record
to all files in its plan. It does not yet apply distinct per-file author/license
records. For a mixed-license archive, preserve it intact with its source notices
and review status, or add a shared per-file provenance handler before unpacking it
into individually usable resources. Merely keeping exceptions in `source_metadata`
is not proof that each extracted resource has received its correct credits.

Saved-scene credit collection sees saved resource dependencies. Runtime-loaded
assets need separate inclusion; an adapter must not claim that a successful scene
scan covers every asset a game might spawn.

## Authentication, pacing and errors

Read documented API-key environment variables or the masked session-only key passed
to `set_session_key()`. Providers without credentials use an empty `key_env` array.
Never save or echo keys, account responses, authorization headers or signed links.
The core public-metadata sanitizer is an additional safeguard, not permission to
pass secrets into metadata.

Check `enabled`/`network_allowed` before initiating source operations. Search,
requested details and downloads authorize the corresponding access; constructors,
local searches and `variants()` do not. Thumbnail fetching must reuse disk images
and be limited to URLs authorized by user searches/downloads. The browser schedules
current-page thumbnails with bounded concurrency and reveals cards after an image
succeeds; the adapter still owns its cache and transport safety. Use the shared
`core/request_transport.gd` and `core/thumbnail_image.gd` mechanics for threaded
HTTP, cancellation completion, authorized image redirects, and worker decoding.

Keep authentication on the documented API origin. Do not forward it to file/CDN
hosts or arbitrary redirects. Use HTTPS, bounded response sizes/timeouts and safe
redirect handling. Respect published limits and Retry-After; pace requests and keep
retries finite. `cancel_all()` should stop outstanding transport when disabled or
removed. Errors should identify the operation and site without dumping private
server responses. Do not bypass login, CAPTCHA or paywalls.

The shared download queue waits five seconds between asset versions by default.
That does not replace source-specific API pacing, and it is not a license to make
unbounded metadata or file requests inside one adapter call.

## Build offline regression tests

Use synthetic, sanitized JSON/HTML fixtures and mocked transport. Override **every**
network path, including details, thumbnails, product pages, redirects and file bytes.
Do not harvest fixtures or probe service limits as an automated setup step.

Cover at least:

- Parsing search/details, missing fields and a representative changed layout.
- Stable identities, pagination completion/repeated cursors, unsupported categories.
- Author versus uploader, exact terms, alternative/mixed licenses and unknown data.
- Real-only versions, model LODs, filter keys and actual versus requested sizes.
- Repeated details/images using cache, optional conditional requests, error handling,
  cancellation, secret stripping and no credential forwarding.
- A mocked source download through preparation to resource sidecars/import receipts,
  local reuse/checkmarks, and saved-scene attribution where the format permits it.
- Coexistence with another provider using the same asset ID, and disabled-site behavior.

Useful references are [`tests/test_providers.gd`](../tests/test_providers.gd),
[`test_cache.gd`](../tests/test_cache.gd),
[`test_search_session.gd`](../tests/test_search_session.gd),
[`test_download_inventory.gd`](../tests/test_download_inventory.gd) and
[`test_batch_cards.gd`](../tests/test_batch_cards.gd).
Run the full offline suite listed in
[`.github/workflows/test.yml`](../.github/workflows/test.yml), plus the new provider's
tests, on supported Godot versions. Add those tests to CI. Do not run the opt-in
live smoke test as part of development automation.

## Document and ship an adapter

Include a provider README with its access method, supported categories/formats,
credential variable names, stable-ID strategy, rate limits, source metadata fields,
known omissions, cache policy and fixture/test commands. Note any manual verification
date without including private download URLs or credentials. If code or assets were
adapted from another project, preserve required notices and confirm compatibility
with this addon's license; inspiration is not permission to copy code.

A provider-specific update should normally contain its directory, fixtures/tests
and documentation. Avoid unrelated map or asset changes. Keep the core and its
contract unchanged when fixing source parsing. If a shared improvement is necessary,
make that boundary change explicit and verify existing providers too.

For manual installation/update:

1. Back up the existing provider directory and any uncommitted local modifications.
2. Copy the reviewed replacement directory into `addons/3dtexel/providers/<id>/`.
3. Keep existing sidecars, original imports and user metadata intact.
4. Toggle **Asset Library** off/on to reconstruct provider discovery and controls.
5. Verify the provider using offline tests; perform only a small authorized online
   check if needed. A working older directory is the rollback package.

Provider directories can be packaged and maintained separately from the core. The
current project has directory discovery and manual replacement, **not** a provider
package manager, automatic updates or runtime compatibility negotiation. Adapters
are trusted executable GDScript, not sandboxed data files. Review their source and
provenance before installing them.

## When the site changes

Reproduce the break with a small sanitized/synthetic fixture. Determine whether the
change is in search pagination, source parsing, metadata interpretation, authentication
or download resolution. Fix that layer in the provider; add the regression fixture;
run its tests and the shared suite. Document changed support and any migration needed.

Keep `descriptor().id`, source asset IDs and version IDs stable whenever they still
refer to the same things. Renaming them breaks catalog identities, imported-version
checkmarks and reuse. Do not fix this by deleting the user's cache or receipts.
If identities genuinely must change, provide a specific migration or legacy lookup
and test it against existing import metadata.

If the common contract must change, update the base class, contract reference and
all bundled adapters/tests together, and publish clear compatibility notes. The
current "contract v1" is a documented interface, not an automatically enforced
version handshake. A website layout change alone should not require a core update.
