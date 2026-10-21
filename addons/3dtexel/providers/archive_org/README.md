# Internet Archive Provider Adapter

Independent Godot 4.4+ editor adapter for [Internet Archive](https://archive.org/) with [Flickr Commons](https://archive.org/details/flickrcommons) integration, implementing Provider Contract v1.

## Supported Features & Capabilities
- **Asset Types**: Images (Flickr Commons), Audio, 3D Models.
- **Collections**: `collection:flickrcommons` by default, extensible to other IA collections.
- **Authentication**: Zero API keys required (`key_env: []`).
- **REST Endpoints**:
  - `GET https://archive.org/advancedsearch.php` (Solr-based field query, pagination)
  - `GET https://archive.org/metadata/{identifier}` (file manifest and structural details)
  - `GET https://archive.org/download/{identifier}/{filename}` (direct file downloads)
  - `GET https://archive.org/services/img/{identifier}` (thumbnail previews)
- **Licensing**: Public Domain / No Known Copyright Restrictions.
- **Attribution**: Preserves institution/creator credit, date, and archive details URL.
- **Pacing & Cache**: 500ms request pacing, disk cache in `user://archive_org_cache`.
