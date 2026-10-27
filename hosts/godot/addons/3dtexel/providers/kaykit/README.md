# KayKit provider

Uses the publisher-owned [KayKit Game Assets repositories](https://github.com/KayKit-Game-Assets)
for free pack archives. No API key is required. This covers the publisher's public
GitHub packs; paid/extra/source releases from itch.io are not offered.

Each submitted search requests one GitHub search page of at most six repositories.
Results must belong to the exact official publisher and must not be forks. The
adapter reads a matching repository's root file listing and its declared license,
then renders its reported pack image. Requests are threaded, paced at 500 ms, and
cancellable. Public GitHub request limits apply. Additional pages require the
shared browser's explicit paging action; no repository trees or entire sites are swept.

Only reported ZIP archive templates are exposed. License and availability are
checked again when resolving a download; missing choices return an error rather
than silently substituting a different file. Unknown/restricted licenses do not
become CC0, and absent creator metadata is not fabricated. Public license text,
source URLs, hashes, credits and import receipts are retained. Source-file links
survive sanitized metadata caching; old incomplete cached listings are refetched.
Cached selection and version rendering require no network calls.

Imports preserve ZIPs intact, including their model files and texture dependencies.
Automatic extraction and ready-to-place scene generation are not implemented.
The existing `kaykit:dungeon_pack` identity is retained for Dungeon Remastered.
Other public repository names supply stable IDs; obsolete cached records without
repository evidence require a fresh search before they can be downloaded.

Live verified on 2026-10-25 with a `dungeon` search, a rendered pack image, and the
Dungeon Remastered ZIP download. The archive passed its integrity check and contains
411 model files; a sample GLB parsed in Godot. This does not verify every public pack.

Offline tests use invented repository metadata, generated image pixels, and a
synthetic model ZIP. Every network path is mocked, including license retrieval.
They exercise search scope/paging, cache sanitization/migration, exact variant
selection, changed-license failures, permission handoff, model decoding,
provenance, hashes and local import reuse. No live data or media is used as a fixture.
