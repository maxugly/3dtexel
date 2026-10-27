# NASA Visible Earth Provider for 3DTexel

Connects 3DTexel to NASA's Visible Earth library, providing the iconic Blue Marble next generation earth mosaics, Black Marble city lights, topography, bathymetry, and seasonal cloud masks.

## Features
- **Earth Textures & Albedo Maps**: Ultra-high resolution global equirectangular maps of Earth.
- **Seasonal & Thematic Layers**: Monthly cloud-free albedo, night-time illumination, digital elevation, and land surface masks.
- **Resolution Variants**: 21600x10800, 5400x2700, and 2048x1024 textures ready for Godot spherical mapping.
- **Offline Tests**: 100% offline contract and unit tests with mock responses.

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
