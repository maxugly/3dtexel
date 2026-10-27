# Freesound provider

Search and sound details use the Freesound API with `FREESOUND_API_KEY` from the
inherited environment (or the existing editor session key control). API keys are
sent in authorization headers only to the exact Freesound API origin. They are
never appended to URLs or forwarded to preview/CDN hosts.

Reported MP3 and OGG previews are downloadable, with quality and extension matching
the selected preview. Missing high-quality files do not fall back to low quality.
Original downloads require `FREESOUND_OAUTH_ACCESS_TOKEN` in the inherited
environment. Reported WAV/MP3/OGG originals are offered only with that token and
an exact, matching Freesound download endpoint. OAuth credentials are sent only
to the API; redirects to file hosts do not receive them. An original selection
without OAuth produces a clear error and never substitutes a preview. Other
original formats are not offered by this adapter. OAuth can also authenticate search.

Waveform previews use the shared threaded image loader and disk cache. Missing
sound details are retrieved on explicit action, then cached. Exact license terms
and versions are preserved; NC/ND are blocked and unknown/share-alike terms need
review. Existing IDs and legacy metadata cache files remain readable.

Tests use synthetic fixtures only; no test contacts Freesound.

References: [API overview](https://freesound.org/docs/api/overview.html),
[resources](https://freesound.org/docs/api/resources_apiv2.html), and
[authentication](https://freesound.org/docs/api/authentication.html).

Live verified on 2026-10-25: a bounded `wind` search, visible waveform in the
addon UI, and a decoded `mp3_hq` download of sound `420319`, with creator, CC0
license, hash and import receipt preserved. OAuth originals are covered offline;
the live pass covers the API-key preview route.
