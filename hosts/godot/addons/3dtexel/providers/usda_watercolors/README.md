# USDA Pomological Watercolor Provider for 3DTexel

Connects 3DTexel to the USDA National Agricultural Library's Pomological Watercolor Collection of 7,500 botanical illustrations of fruits, nuts, berries, and plant cultivars.

## Features
- **Public Domain**: Historical botanical watercolors created by USDA artists between 1886 and 1942.
- **Stylized & Food Textures**: Ideal for UI icons, foliage textures, still-life art, and stylized organic materials.
- **High-Resolution & IIIF Support**: Provides full-resolution scans, 2048px, 1024px, and thumbnail variants.
- **Offline Tests**: 100% offline contract and unit tests with mock responses.

## Adapter behavior

Preview URLs use the shared threaded image loader, exact-URL authorization, and
persistent PNG cache. Connection checks perform one bounded query and propagate
site errors. Legacy metadata cache paths remain readable and are included with
previews in the browser's cache size/clear controls.

Coverage is offline with synthetic fixtures. These checks validate adapter
mechanics, not live endpoint availability or the rights of every upstream item.
