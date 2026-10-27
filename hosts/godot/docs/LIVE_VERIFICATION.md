# Live provider verification — 2026-10-25

Six of the 72 bundled providers completed the required flow. These six start
checked; the other 66 start unchecked. This is a dated, asset-level verification,
not a guarantee that every asset or thumbnail from an enabled provider works.

## Checked by default

- **Kenney** — Nature Kit (`nature_kit`), `zip`. The image rendered in the addon;
  the ZIP opened successfully and contains 3D model files among 3,626 entries.
- **Internet Archive** — Feeding Time (`5229662332_3db4ff073b_o`), `original_jpg`.
  The image rendered in the addon and the downloaded original decoded as an image.
- **Wellcome Collection** — Tree shapes. Pencil drawing. (`z5xjehgf`), `2048`.
  The image rendered in the addon and the downloaded JPG decoded successfully.

- **Freesound** — wind23.m4a (`420319`) by tonik-95, `mp3_hq` (CC0 1.0).
  The waveform rendered in the addon and the downloaded MP3 decoded successfully.
  This verifies the API-key preview route; OAuth originals have offline coverage
  and have not been live verified. Search requires an inherited Freesound credential.

- **KayKit** — Dungeon Remastered (`dungeon_pack`), `zip` (CC0 1.0).
  The published pack image rendered in the addon. The 6,339,806-byte archive
  passed its integrity check, contains 411 model files, and a sample embedded GLB
  parsed successfully in Godot. The archive remains intact on import.

- **3D Texel** — Wood Shingle Roof (`24263`) by Lucas Anton Gomez (CC0).
  Material thumbnails rendered in the addon. A zero-credit download returned
  five 2048×2048 maps and a native material that reloaded successfully. The server
  returned `2k` for a `1k` request; the import receipt records both sizes and the
  UI marks the actual `2k` version downloaded. Search used the `wood` query.

All six downloads have saved provenance, credit sidecars, hashes, and imported
version receipts. Screenshots visibly show each corresponding downloaded tile.
The local evidence and downloaded assets from this run are under the ignored
`hosts/godot/AssetLibrary/live-verification/2026-10-25/` directory.

## Other providers

Unchecked means the complete flow was not verified in this environment. This
includes missing credentials, unavailable endpoints, empty results, absent UI
images, unsupported download content, or an incomplete download path. It does
not mean the upstream service is permanently broken.

The per-provider public stage results, queries, failure reasons, and successful
asset/version IDs are in
[`provider_verification.json`](../addons/3dtexel/provider_verification.json).
No credentials, raw provider responses, or signed download URLs are included.

Recorded reasons for remaining unchecked:

- asset import failed: 1
- connection failed: 5
- credentials not configured: 8
- download resolution failed: 1
- download url not https: 1
- downloaded content invalid: 1
- http 401: 1
- http 403: 6
- http 404: 22
- http 406: 1
- http 503: 1
- no confirmed free download: 1
- no downloadable asset: 2
- no image in ui: 4
- no search results: 8
- only thumbnail download available: 1
- search timeout: 2

## Method and limits

Checks used the real addon browser, provider transport, download action, and
preparation/inventory code, rendered with Godot's OpenGL compatibility renderer
in Xvfb. This was an explicitly user-authorized live check, separate from offline
CI. No mocks or cached offline fixtures were used as proof of live functionality.

Searches were bounded to a submitted page. Up to three candidate assets and two
reported choices per candidate were considered. Only confirmed free, zero-credit
assets with recognized terms were downloaded. An image's own thumbnail was not
accepted as its separate asset download. ZIPs were opened, images/audio decoded,
GLBs parsed where applicable, and provenance plus content hashes checked. Unverified
partial download artifacts were removed; failed check reports were retained.

Provider pacing was retained. Openverse received a second bounded NASA query to
look for eligible source licenses; advertised public access was also tried for
Europeana, itch.io, and Paris Musées without credentials. No site-wide crawling,
account-response collection, paid imports, or credit expenditure was performed.

## Default behavior

Old saved opt-ins do not override the new verified-only defaults. A user can still
explicitly enable a site in Settings when returning to repair or investigate it.
Selecting an unchecked source or entering credentials alone does not enable it.
Reload the addon (or reopen the project) to reconstruct the checkboxes after this
update. Normal startup reads the checked-in evidence and performs no live checks.
