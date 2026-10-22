# 3D Asset Library

A provider-neutral asset library for 3D models, PBR materials, images, and audio.

The repository contains two hosts over the same provider knowledge:

- `app/` — standalone Node.js/TypeScript library, MCP server, HTTP API, and CLI.
- `hosts/godot/` — the original Godot 4.4+ editor addon, preserved as a separate host.

Both are MIT-licensed. Provider metadata and downloaded assets remain subject to their own licenses. See [ATTRIBUTION.md](ATTRIBUTION.md).

## Standalone app

```bash
cd app
npm install
npm run build
node dist/cli.js providers
```

Run one search and inspect the plan before importing:

```bash
node dist/cli.js search brick --providers polyhaven --category material
node dist/cli.js plan polyhaven:brick_wall_001 --variant 1k
node dist/cli.js download polyhaven:brick_wall_001 --variant 1k
```

The app exposes the same functionality through:

- a TypeScript API
- an MCP stdio server (`asset-library-mcp`)
- a local HTTP JSON API (`asset-library serve`)
- a CLI (`asset-library`)

See [app/README.md](app/README.md) for provider configuration, MCP/HTTP setup, data layout, and security behavior.

Default imports are free and zero-credit. The library refuses restricted or paid assets and records creator, license, and provenance sidecars beside each import. API keys are read only from the inherited environment and are never written to the catalog, cache, or logs.

## Godot addon

The Godot host retains its editor browser, provider adapters, material import, and offline tests:

```bash
godot --headless --path hosts/godot -s tests/test_core.gd
```

Open `hosts/godot/project.godot` in Godot 4.4+ to use the editor addon. Godot-specific provider documentation remains in `hosts/godot/docs/`.

## Development

```bash
cd app
npm run check          # typecheck source and tests, run offline tests, build
```

All automated tests are offline and use mocks or checked-in fixtures. Live provider checks are explicit opt-in actions and are never part of CI.
