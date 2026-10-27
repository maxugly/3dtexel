# Openverse provider

Searches image and audio metadata through the Openverse API. Queries are bounded
and anonymous pages use at most 20 results. Pagination follows the reported page
count. API details are fetched only when needed and cached for reuse.

The landing page is preserved as the asset's provenance URL; downloads use the
separate reported media URL. Waveform images are never offered as audio streams.
Only reported file choices appear. Missing or unsupported formats return an error
rather than downloading a landing page or substituting another version.

CC terms and reported versions are retained, including NC, ND, and share-alike
qualifiers. Unknown terms require review. Previews use the shared threaded loader
and disk cache. Existing normalized IDs and legacy metadata files remain readable.

Tests use synthetic fixtures only. Offline tests validate the adapter's behavior;
they do not establish live availability of upstream assets.

Reference: [Openverse API](https://api.openverse.org/v1/) and
[media properties](https://docs.openverse.org/meta/media_properties/catalog.html).
