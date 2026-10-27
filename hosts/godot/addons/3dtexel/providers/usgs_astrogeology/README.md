# USGS Astrogeology Planetary Maps Provider for 3DTexel

Connects 3DTexel to the USGS Astrogeology planetary cartography archives, delivering equirectangular planetary albedo, shaded relief, and digital elevation mosaics for space simulation and skyboxes.

## Features
- **Solar System Cartography**: Global surface maps of Mars, Moon, Mercury, Venus, Pluto, Ceres, Callisto, Ganymede, and Europa.
- **PBR Planet Shading**: Equirectangular maps ready for Godot spherical mapping, skyboxes, and celestial bodies.
- **Resolution Variants**: Support for 8K, 4K, and 2K resolution textures.
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
