# BlenderKit Provider

Adapter for browsing and downloading confirmed-free 3D models from BlenderKit (https://www.blendkit.com).

## Capabilities

- Asset Types: 3D Models (`model`)
- Variants: `gltf_godot`, `gltf`, `blend`
- URL / UUID lookup: paste gallery URLs (e.g. `https://www.blendkit.com/asset-gallery-detail/<uuid>/`) or asset UUIDs directly in search.
- Policy: Confirmed free models only (`isFree: true`). Paid / subscription assets are strictly blocked.
- Authentication: Public free mode works anonymously without credentials. Optional API access token can be set via `BLENDERKIT_API_KEY`, `BLENDERKIT_TOKEN`, session key, or `~/.config/blenderkit_token.json`.
