# 3D Texel provider

Uses the [official REST API](https://3dtexel.com/developers/) for bounded PBR material
searches, details and download resolution. Material search and thumbnails need no
key. Downloads use `3D_TEXEL_API_KEY`, with `3DTEXEL_API_KEY`, `TEXEL_API_KEY`, and
`TEXEL` retained as aliases, or an existing session key. The addon reads inherited
environment variables; it never writes credentials. Authorization is sent only to
the fixed HTTPS API origin, with redirects disabled. File hosts receive no key.

Submitted searches request at most 24 matches per source page. Other categories
remain unsupported by this adapter. API calls are threaded, cancellable and paced
at one per second. Selection and repeated details reuse cached metadata. Actual
reported author/resolution fields can be enriched from the selected product page;
no creator or resolution is guessed. Reported sizes survive shared catalog reloads.

The API's explicit `CC0 1.0 (public domain)` declaration maps to canonical CC0.
Other license versions and restrictions are preserved. Downloads revalidate current
price, API availability and license before requesting links. Only a reported
resolution is accepted, every download POST sets `max_credits: 0`, and the response
must confirm `charged_credits: 0`. Paid, unknown, NC/ND or proprietary assets are
blocked. Signed links and account responses remain in memory and never enter caches
or sidecars. The actual returned size is recorded, including server substitutions.

Native material preparation preserves source maps, creator/license sidecars,
content hashes, dimensions, the prepared material and the import receipt. Existing
Texel cache paths and legacy import discovery remain compatible.

Live verified on 2026-10-25: a `wood` search showed material thumbnails. Wood Shingle
Roof (`24263`) by Lucas Anton Gomez downloaded five maps at zero credits, and its
native material reloaded. Requested 1K returned 2K; the receipt and UI record 2K,
with 2048×2048 source maps. This verifies one asset rather than the entire catalog.

Offline tests mock every API, page and image request. They cover the key alias,
license parsing, reported variants after catalog persistence, cached details,
zero-credit caps, updated-price/license rejection, exact version selection, native
material preparation, source hashes, sidecars and signed-link exclusion. Live
checks are manual and separate from CI.
