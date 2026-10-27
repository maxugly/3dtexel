# Scan The World Provider for 3DTexel

Connects 3DTexel to Scan The World's open cultural heritage repository of 10,000+ 3D sculpture and statue scans.

## Features
- **Cultural Heritage 3D Scans**: High quality photogrammetry and 3D scans of masterpieces from the Louvre, British Museum, Vatican, and world museums.
- **Ready for Godot**: Direct GLB and OBJ downloads for import into Godot 4.4+.
- **Museum Provenance**: Retains artwork title, original sculptor/era, and museum holding location.
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
