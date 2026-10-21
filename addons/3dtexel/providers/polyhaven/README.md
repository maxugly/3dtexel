# Poly Haven Provider Adapter

Independent Godot 4.4+ editor adapter for [Poly Haven](https://polyhaven.com/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: Materials (PBR Textures), 3D Models, HDRIs (Images).
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **REST Endpoints**:
  - `GET https://api.polyhaven.com/assets` (full catalog query, type filtering)
  - `GET https://api.polyhaven.com/info/{id}` (asset dimensions, descriptions, author credits)
  - `GET https://api.polyhaven.com/files/{id}` (multi-resolution maps, model formats)
- **Licensing**: CC0 1.0 Universal (Public Domain).
- **Attribution**: Preserves author/artist credits and Poly Haven source URLs.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://polyhaven_cache`.
