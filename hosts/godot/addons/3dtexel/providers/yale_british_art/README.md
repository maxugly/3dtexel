# Yale Center for British Art Provider for 3DTexel

Connects 3DTexel to the Yale Center for British Art (YCBA), home to paintings, sculpture, prints, drawings, and rare books illustrating British art and culture from the Elizabethan period onward.

## Features
- **Master British Art**: Notable works by J.M.W. Turner, John Constable, Thomas Gainsborough, and William Blake.
- **Multiple Resolutions**: High-res original scans, 2048px, 1024px, and thumbnail previews via IIIF.
- **In-Game Art & Environmental Decals**: Atmospheric landscapes, marine seascapes, Victorian portraiture, and historical manor art.
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
