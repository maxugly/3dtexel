# Heritage Type Provider for 3DTexel

Connects 3DTexel to Heritage Type Co.'s vintage vector engravings, decorative ornaments, floral banners, and heraldic embellishments.

## Features
- **Vintage Decorative Ornaments**: Clean high-contrast PNG line art and raster plates ready for alpha masking and decals.
- **Multiple Resolutions**: High-res original assets, 2048px, 1024px, and thumbnail previews.
- **Ideal for Game UI & Decals**: Great for inventory frames, map borders, quest journal headers, and stylized emblems.
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
