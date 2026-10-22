# ambientCG Provider Adapter

Independent Godot 4.4+ editor adapter for [ambientCG](https://ambientcg.com/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: Materials (PBR Textures), 3D Models, HDRIs.
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **REST Endpoints**:
  - `GET https://ambientcg.com/api/v3/assets` (search, category filtering, offset pagination)
  - `GET https://ambientcg.com/get?preview={id}` (thumbnail previews)
  - `GET https://ambientcg.com/get?file={file}` (multi-resolution ZIP downloads)
- **Licensing**: CC0 1.0 Universal (Public Domain).
- **Attribution**: Preserves creator credit to Lennart Demes and ambientCG source URLs.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://ambientcg_cache`.
