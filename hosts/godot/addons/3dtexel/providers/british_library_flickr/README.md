# British Library Flickr Commons Provider for 3DTexel

Connects 3DTexel to the British Library's 1M+ digitized public domain illustrations and engravings hosted on Flickr Commons.

## Features
- **Public Domain**: Over 1,000,000 digitized historical plates, mechanical diagrams, architectural cuts, and vintage maps.
- **Direct Image Delivery**: Direct CDN resolution selection (original, large 1024, medium 640, small 240).
- **Metadata Preservation**: Book title, page number, author, publisher, and Flickr item links preserved in metadata sidecars.
- **Offline Tests**: 100% offline unit and contract tests with mock responses.

## Adapter behavior

Preview URLs use the shared threaded image loader, exact-URL authorization, and
persistent PNG cache. Connection checks perform one bounded query and propagate
site errors. Legacy metadata cache paths remain readable and are included with
previews in the browser's cache size/clear controls.

Download choices come from reported file records or explicit media URL fields.
An unavailable version returns an error; another file is never substituted or
relabeled with an invented resolution. Source metadata survives catalog reloads.

Coverage is offline with synthetic fixtures. These checks validate adapter
mechanics, not live endpoint availability or the rights of every upstream item.

Flickr API searches require `FLICKR_API_KEY` (or the editor session key control).
Without a key the adapter is off by default. Keys are used only for the exact API
endpoint and are never persisted, logged, or forwarded to image hosts. Flickr's
numeric license codes are interpreted separately; "No known copyright restrictions"
is preserved for review rather than rewritten as a public-domain dedication.
See [Flickr API licenses](https://m.flickr.com/services/api/flickr.photos.licenses.getInfo.html).
