# itch.io Provider Adapter

Independent Godot 4.4+ editor adapter for [itch.io](https://itch.io/game-assets) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: 3D Models, 2D Sprites/Images, Audio/SFX, Materials.
- **Authentication**: `ITCHIO_API_KEY` passed via environment or in-memory session token. Public browse feeds work without keys.
- **Feed & API Endpoints**:
  - `GET https://itch.io/game-assets/free.xml` (RSS feed for free game assets)
  - `GET https://itch.io/game-assets/free/tag-{category}.xml` (category-specific feeds)
  - `GET {project_url}/download` (transient download resolution)
- **Licensing**: Creator-declared terms, Creative Commons, CC0.
- **Attribution**: Preserves creator name, project link, and attribution notice.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://itch_io_cache`.
