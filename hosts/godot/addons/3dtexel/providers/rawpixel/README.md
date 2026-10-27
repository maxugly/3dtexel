# Rawpixel Public Domain Provider for 3DTexel

Connects 3DTexel to Rawpixel's curated collection of CC0 public domain vintage illustrations, fine art paintings, botanical plates, antique patterns, and design graphics.

## Features
- **Curated CC0 Fine Art & Graphics**: Digitally enhanced and restored historical artworks under CC0.
- **Multiple Resolutions**: Support for Original High-Res, 2048px, 1024px, and 512px previews.
- **Museum & Artist Provenance**: Captures original artist, museum source, and clean tags.
- **Offline Tests**: 100% offline contract and regression tests with mock client responses.

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
