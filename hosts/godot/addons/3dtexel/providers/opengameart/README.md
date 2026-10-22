# OpenGameArt Provider

Adapter for browsing, previewing, and importing assets from [OpenGameArt.org](https://opengameart.org/content/).

## Access method and authentication

- **Base site**: `https://opengameart.org`
- **Search endpoint**: `https://opengameart.org/art-search`
- **Asset detail pages**: `https://opengameart.org/content/<slug>` or `https://opengameart.org/node/<id>`
- **Direct file host**: `https://opengameart.org/sites/default/files/`
- **Credentials**: None (`key_env: []`). All assets on OpenGameArt are free and open source. No API key or user authentication is required.

## Supported categories and formats

- **Supported categories**:
  - `all`: queries all art types.
  - `model`: filters to 3D Art (`field_art_type_tid[]=10`).
  - `material`: filters to Textures (`field_art_type_tid[]=14`).
  - `audio`: filters to Music and Sound Effects (`field_art_type_tid[]=12&field_art_type_tid[]=13`).
  - `image`: filters to 2D Art and Concept Art (`field_art_type_tid[]=9&field_art_type_tid[]=11`).
- **File formats supported**: GLB, GLTF, OBJ, FBX, BLEND, PNG, JPG, JPEG, WEBP, TGA, EXR, HDR, WAV, OGG, MP3, ZIP, 7Z, TAR, GZ, TXT, MD, PDF.
- Download preparation uses the core `files` kind plan. Archives remain intact with sidecar attribution.

## Stable ID strategy

- **Asset ID**: Extracted path slug from the canonical asset URL `/content/<slug>` (e.g. `dungeon-chest-3d`). If the URL references a node path `/node/<id>`, the numeric node ID is used. Both are opaque strings.
- **Provider-qualified identity**: `opengameart:<slug>`, ensuring no collision with other site providers.
- **Variant ID**:
  - For single-file submissions: `original` with format filter key `format:<ext>`.
  - For multi-file submissions: `all-files` (to download the full collection) and safe lowercase slugs of individual filenames (e.g. `chest_glb`, `chest_blend`).

## Creator and license evidence

- **Authorship**: Explicitly declared author names in the `field-name-field-art-author` section take precedence over site uploaders/submitters. If no author is explicitly declared, the uploader is recorded and marked with source evidence.
- **Attribution notice**: Captured verbatim from the site's `Copyright/Attribution Notice` field (`field-name-field-art-attribution`) and saved into `attribution_text` and companion credits sidecars.
- **Licenses**: Full preservation of all declared licenses in `licenses: Array`. The preferred commercial/permissive alternative (e.g. CC0, CC-BY 3.0/4.0, OGA-BY 3.0) is selected as `selected_license` and `license`. Share-alike (CC-BY-SA) and copyleft terms (GPL) are tracked and flagged for review according to project policy.

## Rate limiting and pacing

- Minimum 500ms pacing between outgoing network requests (`pace_request()`).
- Bounded concurrency with safe HTTPS redirects and size limits (max 8MB for search/detail HTML, max 64MB for source downloads).
- Auth headers are never forwarded to download or CDN hosts.

## Cache policy

- Cache directory: `user://opengameart_cache`.
- HTML responses and metadata are cached on disk and validated via HTTP validators (`ETag`, `Last-Modified`) using conditional requests (`If-None-Match`, `If-Modified-Since`).
- Account, login, and registration responses are never cached.
- Thumbnails are downloaded only when authorized by user search or download actions and stored locally.

## Testing and verification

- Run offline provider tests:
  ```bash
  godot --headless --path . -s tests/providers/opengameart/test_opengameart.gd
  ```
- Run the full offline suite:
  ```bash
  godot --headless --path . -s tests/test_core.gd
  ```
