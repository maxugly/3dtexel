# Prompt for Antigravity: add providers to Asset Library

Work in `/home/m/snc/cod/3dtexel`, our independent MIT Godot 4.4+ addon, installed
in `/home/m/snc/cod/scrappersDelight/addons/3dtexel/`. Read `AGENTS.md`,
`docs/PROVIDERS.md`, `core/provider.gd` (under the addon), the Texel adapter, and
`tests/test_providers.gd` before editing. The GitHub repo is
https://github.com/maxugly/3dtexel . Keep the existing addon path stable.

Add **OpenGameArt** first. Subsequently add **Poly Haven** and **ambientCG** as
provider adapters in this same addon. Do not create three more Godot plugins or
fork three copies of the browser. Do not remove the user's currently working
separate Poly Haven/ambientCG addons until their replacements are verified and
the user authorizes that cleanup. Complete each provider before starting the next.

The core owns the UI, local catalog, multi-site search, site enable/disable and
session-key controls, pagination, generic variant checkboxes, native preparation,
sidecars and saved-scene credits. Adapters translate provider-specific search,
metadata, variants, thumbnail access and downloads into the existing contract.
Directory discovery registers `providers/<id>/provider.gd` automatically. A provider
must not need edits to browser.gd, a second main-screen tab, an autoload, Python,
a daemon, or a parallel credit schema. Small shared core improvements are welcome
when a real format requires them, with migration and offline regression tests.

Our central requirement: **creator and license metadata must travel WITH every
resource**. Never leave it only in a user-local database. Preserve explicit author
names/URLs, contributors, requested attribution, source and license URLs/text/versions,
raw sanitized public metadata, selected license, alternative/cumulative terms,
file-specific exceptions, original files, hashes, and transformations. Propagate
that provenance through derived scenes/materials/textures and terrain handoffs.
Use the existing `.credits.json`/folder `asset.credits.json` convention and scene
collector. Never invent an author, treat the uploader/site as creator without evidence,
or turn unknown licenses into CC0. Scene traversal only sees saved dependencies;
dynamic resources need explicit inclusion. Test metadata survival, not just downloads.

Four workflow statuses already exist: permissive/no-credit-required, unknown/review,
commercial-with-attribution, blocked-for-this-project. Keep exact licenses in addition
to this status and reason. "Free download" does not mean CC0. CC-BY-SA/GPL may permit
commercial use with additional obligations: do not label them attribution-only or
universally undistributable. Keep them under review unless explicit project policy
handles the obligations. OpenGameArt submissions can offer alternative licenses;
record all of them and the chosen valid option. Mixed-license packs must retain
per-file credits and must not be flattened into one permissive license. The site
FAQ is https://opengameart.org/content/faq and OGA-BY guidance is
https://opengameart.org/content/oga-by-30-faq . Verify current official documentation
when implementing; do not assume an API or undocumented endpoints exist.

Match existing cache-first behavior: opening Godot, typing, selecting, filtering,
paging and changing variants are LOCAL. Only explicit Refresh, Refresh selected
metadata, Check connection or Download authorizes network. Persist metadata and
thumbnails; reuse completed downloads; no background expiration or polling.
Respect published site access policies, robots/terms, rate limits, Retry-After,
and cancellation. No rapid retries, scraping an entire site, account bypasses,
paid downloads or speculative resolution/file probes. If a documented API/feed
is unavailable, use a permitted bounded page reader, or support explicit pasted
asset URLs first and explain the limitation. Ordinary browsing must remain useful
from cache when offline. No keys should be requested for sites that do not need them.
Secrets come from documented inherited env vars or masked session-only fields;
never commit/save/log keys or cache signed download URLs/account data.

OpenGameArt includes models, textures, 2D art and audio. Populate actual format/file
variants rather than fictitious resolution choices. Use `material` plans for known
PBR maps and `files` plans for other sources. The existing generic source handler
preserves archives intact; if importing packs needs extraction, add a shared safe
archive handler with traversal/symlink/size checks and provenance for every extracted
file. Keep all supplied licenses/readmes. Do not assume copying a ZIP is the same
as a ready-to-place Godot model. Preserve stylized textures, wear masks and correct
scale. Do not modify our game maps, assets or art direction just to test browsing.

**All automated tests and previews must be offline**, using checked-in synthetic
fixtures and mocked transport. Do not pound provider APIs to discover limits or
fill caches. Do not run test_live.gd. Validate search parsing, page cursors, unknown
fields, licensing variants and per-file credits, author versus uploader, rate/error
handling, cancellation, source checksums, source→prepared→scene sidecars, cross-site
ID collisions, disabled sites, no-key public providers and imported-source reuse.
Use existing fixtures wherever possible. Any manual online verification should be
minimal and user-triggered, never a broad sweep.

Deliver provider code, offline tests and documentation of supported categories,
formats, metadata limitations and access method. Run the full offline suite on
Godot 4.4.1 and our 4.7.2 when available, copy updated addon files into the game's
installed addon without disturbing unrelated work, preserve provenance, and report
what is ready and any unsupported import formats. Do not change GitHub visibility,
rename repositories, remove other plugins, or publish releases without authorization.
