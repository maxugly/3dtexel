# 3DTextures.me Provider Adapter

Independent Godot 4.4+ editor adapter for [3DTextures.me](https://3dtextures.me/) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: PBR Materials (PBR Textures).
- **Authentication**: Zero API keys or tokens required (`key_env: []`).
- **REST Endpoints**: WordPress REST API (`/wp-json/wp/v2/posts`).
- **PBR Channels**: Resolves direct URLs for Color, Normal, Roughness, Height/Displacement, and Ambient Occlusion.
- **Licensing**: CC0 1.0 Universal (Public Domain).
- **Attribution**: Preserves 3DTextures.me source attribution and post links.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://3dtextures_cache`.
