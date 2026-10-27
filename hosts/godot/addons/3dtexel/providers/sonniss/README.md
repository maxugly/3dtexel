# Sonniss GDC Audio Archives Provider for 3DTexel

Connects 3DTexel to Sonniss's GDC sound library releases, featuring professional-grade, multi-channel sound effects, cinematic whooshes, creature roars, industrial machinery, weapons, Foley, and ambient atmospheres.

## Features
- **Studio-Grade Game SFX**: Weapons, mechanical impacts, atmospheric drones, sci-fi UI, footsteps, creatures, and environmental ambience.
- **Multiple Audio Formats**: Previews and master audio in WAV and OGG format.
- **Commercial Game Ready**: Permissive royalty-free usage with no required attribution in published games.
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
