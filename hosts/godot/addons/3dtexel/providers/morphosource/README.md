# MorphoSource Provider for 3DTexel

Connects 3DTexel to MorphoSource's 20,000+ open-access 3D scans of biological specimens, skeletons, skulls, fossils, and museum artifacts.

## Features
- **Open Biological & Paleontological Scans**: Real museum specimen photogrammetry and micro-CT surface meshes.
- **3D Formats**: Direct GLB and OBJ downloads compatible with Godot 4.4+.
- **Taxonomic & Specimen Metadata**: Preserves binomial names, skeletal elements, museum specimen numbers, and repository credits.
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
