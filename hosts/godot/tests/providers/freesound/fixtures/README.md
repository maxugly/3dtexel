# Offline Freesound fixtures

`sounds.json` contains invented sound metadata and public URL shapes, never credentials.
`preview.mp3`, `preview.ogg`, and `original.wav` are synthetic 0.15-second 440 Hz
sine waves generated locally with FFmpeg (mono, 22,050 Hz; MP3 32 kbps,
Vorbis quality 1, WAV PCM signed 16-bit). No provider media was used.
These project-authored fixtures are provided under the repository MIT license.
The tests mock every transport call and decode imported audio and verify its
credit sidecars, hashes, exact variants and permission handoff.
