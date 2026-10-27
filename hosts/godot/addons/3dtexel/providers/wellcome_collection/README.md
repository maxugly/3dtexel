# Wellcome Collection Provider for 3DTexel

Connects 3DTexel to the Wellcome Collection's vast open digital library of anatomical diagrams, medical illustrations, botanical manuscripts, and scientific prints.

## Features
- **Open Cultural & Scientific Heritage**: Over 100,000 digitized historical plates and works.
- **IIIF Integration**: Supports dynamic IIIF image resolutions (full/max, 2048px, 1024px, 512px).
- **Automated Attribution**: Captures author, title, institution, and CC-BY 4.0 license metadata into sidecars.
- **Offline Tests**: 100% offline contract and unit tests with mock responses.

## Adapter behavior

Preview URLs use the shared threaded image loader, exact-URL authorization, and
persistent PNG cache. Connection checks perform one bounded query and propagate
site errors. Legacy metadata cache paths remain readable and are included with
previews in the browser's cache size/clear controls.

Coverage is offline with synthetic fixtures. These checks validate adapter
mechanics, not live endpoint availability or the rights of every upstream item.
