# Grab3D Provider Adapter

Independent Godot 4.4+ editor adapter for [Grab3D](https://grab3d.com/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: 3D Models (Props, Characters, Kits, Items).
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **REST Endpoints**:
  - `GET https://grab3d.com/api/v1/models.json` (complete models directory)
  - `GET https://grab3d.com/api/v1/models/{slug}.json` (single model details & specs)
- **Licensing**: CC0 1.0 Universal (Public Domain).
- **Attribution**: Preserves Grab3D attribution notices and source links.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://grab3d_cache`.
