# Sketchfab Provider for 3DTexel

Provider adapter for downloading Creative Commons 3D models from Sketchfab.

## Capabilities
- Search downloadable CC models (`CC0`, `CC-BY`, `CC-BY-SA`).
- Non-commercial (NC), no-derivatives (ND), and paid store models are blocked per zero-credit / permissive policy.
- Formats: `glb` (standard), `gltf` (archive), and `source` (original archive).
- Integrates with 3DTexel automatic model grounding ($Z=0$), origin centering, and `.credits.json` provenance sidecars.

## Credentials
Set `SKETCHFAB_API_KEY` in environment, or input during editor session in 3DTexel Settings.
