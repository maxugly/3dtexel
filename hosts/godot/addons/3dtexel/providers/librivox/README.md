# LibriVox Provider for 3DTexel

Connects 3DTexel to LibriVox's expansive repository of public domain spoken word recordings, poetry, classical mythology, detective mysteries, radio plays, and historical narratives.

## Features
- **Spoken Word & Narratives**: Thousands of complete books and dramatic readings (H.G. Wells, Edgar Allan Poe, Arthur Conan Doyle, Shakespeare, Mary Shelley).
- **In-Game World Audio**: Perfect for vintage in-game phonographs, lore audio logs, radio transmissions, NPC ambient storytelling, and horror recitations.
- **Multiple Audio Formats**: 128kbps MP3 and 64kbps MP3 audio streams.
- **Offline Tests**: 100% offline contract and regression tests with mock client responses.

## Adapter behavior

Preview URLs use the shared threaded image loader, exact-URL authorization, and
persistent PNG cache. Connection checks perform one bounded query and propagate
site errors. Legacy metadata cache paths remain readable and are included with
previews in the browser's cache size/clear controls.

Download choices come from reported file records or explicit media URL fields.
An unavailable version returns an error; another file is never substituted or
relabeled with an invented resolution. Source metadata survives catalog reloads.

The legacy `mp3_128` choice ID is retained for existing archive receipts, but its
label describes the actual audio archive. ZIP archives retain `.zip` filenames;
no bitrate or OGG version is inferred when the source omits that information.

Coverage is offline with synthetic fixtures. These checks validate adapter
mechanics, not live endpoint availability or the rights of every upstream item.
