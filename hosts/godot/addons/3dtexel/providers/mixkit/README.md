# Mixkit Audio Provider for 3DTexel

Connects 3DTexel to Mixkit's library of royalty-free game sound effects, UI clicks, transitional whooshes, fantasy spells, arcade chimes, and environmental Foley.

## Features
- **Categorized Game Audio**: UI clicks, game over fanfare, power-ups, retro bleeps, nature sounds, and cinematic transitions.
- **Ready for Godot Engines**: High-fidelity MP3 and WAV sound clips ready to drop into AudioStreamPlayer nodes.
- **Zero Attribution Required**: Safe for commercial game deployment without forced credit screens.
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
