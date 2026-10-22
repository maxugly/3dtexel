# cgBookcase Provider Adapter

Independent Godot 4.4+ editor adapter for [cgBookcase](https://www.cgbookcase.com/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: PBR Materials (Wood, Metal, Fabric, Tile, Stone).
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **PBR Channels**: Resolves direct URLs for Base Color, Normal, Roughness, Height, and Ambient Occlusion.
- **Licensing**: CC0 1.0 Universal (Public Domain).
- **Attribution**: Preserves creator credit to Dorian Zgraggen (cgBookcase).
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://cgbookcase_cache`.
