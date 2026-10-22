# CGTrader Provider Adapter

Independent Godot 4.4+ editor adapter for [CGTrader](https://www.cgtrader.com/3d-models/character) implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: 3D Models (Focusing on Characters & Avatars).
- **Free Tier Policy**: All queries strictly enforce `free=1` to ensure default imports never spend credits or require payment.
- **Authentication**: `CGTRADER_API_TOKEN` or `CGTRADER_CLIENT_ID` passed via environment or in-memory session token.
- **REST Endpoints**:
  - `GET https://api.cgtrader.com/v1/models` (search, character category filtering, free models filter)
  - `GET https://api.cgtrader.com/v1/models/{id}` (polygon counts, vertex counts, format files)
  - `GET https://api.cgtrader.com/v1/models/{id}/files/{file_id}/download` (transient download resolution)
- **Licensing**: CGTrader Royalty Free License (Free Tier).
- **Attribution**: Preserves creator username, profile URL, and CGTrader catalog link.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://cgtrader_cache`.
