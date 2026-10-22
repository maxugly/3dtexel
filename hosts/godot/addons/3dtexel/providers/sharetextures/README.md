# ShareTextures Provider Adapter

Independent Godot 4.4+ editor adapter for [ShareTextures](https://www.sharetextures.com/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: PBR Materials (Textures).
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **PBR Channels**: Resolves direct URLs for Diffuse/BaseColor, Normal, Roughness, Displacement/Height, and Ambient Occlusion.
- **Licensing**: Custom CC0 grant (personal and commercial use in games permitted; no redistribution of raw collections/libraries).
- **Attribution**: Preserves ShareTextures source attribution and URLs.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://sharetextures_cache`.
