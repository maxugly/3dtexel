# The J. Paul Getty Museum Provider for 3DTexel

Connects 3DTexel to The J. Paul Getty Museum's Open Content Program, giving access to high-resolution master paintings, antiquities, manuscripts, and decorative arts.

## Features
- **Master Artworks**: Includes masterpieces by Van Gogh (Irises), Rembrandt, Monet, Manet, and classical antiquities.
- **Multiple Resolutions**: High-res original master scans, 2048px, 1024px, and thumbnail previews.
- **In-Game Art & Material Decals**: Perfect for framed museum art, baroque interiors, canvas decals, architectural frescoes, and environmental textures.
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
