# asset-library

Provider-neutral 3D, material, image, and audio asset library for Node.js, with a reusable TypeScript API, MCP server, HTTP JSON API, and CLI.

The library searches public asset sites, normalizes their metadata, validates licenses, and imports only confirmed-free, zero-credit assets. It preserves creator/license records and provenance beside every download.

## Requirements

- Node.js 20.11 or newer
- Optional: an API key for providers that require one (currently 3D Texel)

## Install and build

```bash
cd app
npm install
npm run build
```

Run the complete local check:

```bash
npm run check
```

## Quick start

```bash
# List providers (no network)
node dist/cli.js providers

# Search Poly Haven and cache the results locally
node dist/cli.js search brick --providers polyhaven --category material --limit 10

# Inspect a result
node dist/cli.js variants polyhaven:brick_wall_001

# Check the download plan without writing files
node dist/cli.js plan polyhaven:brick_wall_001 --variant 1k

# Import a material
node dist/cli.js download polyhaven:brick_wall_001 --variant 1k

# Review imports and credits
node dist/cli.js imports
node dist/cli.js credits polyhaven:brick_wall_001 --variant 1k
```

Add `--json` to any command for machine-readable output.

## Providers

| ID | Content | Credentials |
| --- | --- | --- |
| `polyhaven` | PBR materials, models, HDRIs | None |
| `ambientcg` | PBR materials, models | None |
| `opengameart` | Materials, models, audio, images | None |
| `openverse` | Images, audio | None |
| `met_museum` | Images | None |
| `wikimedia` | Images, materials | None |
| `nasa` | Images, audio, models | None |
| `kenney` | Models, audio, materials, images | None |
| `texel` | PBR materials | `3DTEXEL_API_KEY`, `TEXEL_API_KEY`, or `TEXEL` |

Texel is disabled for downloads when no key is configured. Poly Haven, ambientCG, OpenGameArt, Openverse, the Met, Wikimedia, NASA, and Kenney require no key.

## MCP

Build first, then register the stdio server with an MCP client:

```json
{
  "mcpServers": {
    "asset-library": {
      "command": "node",
      "args": ["/absolute/path/to/3dtexel/app/dist/mcp.js"],
      "env": {
        "ASSET_LIBRARY_HOME": "/absolute/path/to/asset-library-data"
      }
    }
  }
}
```

Tools:

- `list_providers`
- `search_assets`
- `get_asset`
- `list_variants`
- `plan_download`
- `download_asset`
- `download_assets`
- `list_imports`
- `get_credits`
- `check_provider`

Construction reads local configuration only. `list_providers`, `list_imports`, `get_credits`, and catalog-only searches make no network requests. Search, details, provider checks, and downloads contact providers only when explicitly invoked.

## HTTP API

```bash
ASSET_LIBRARY_TOKEN="replace-me" node dist/cli.js serve --host 127.0.0.1 --port 7575
```

When `ASSET_LIBRARY_TOKEN` is set, send `Authorization: Bearer <token>` on every request, including `/health`. Binding to a non-loopback address without a token is refused.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Readiness and version |
| `GET` | `/v1/providers` | Provider capabilities and credential status |
| `GET` | `/v1/search?q=&category=&providers=&limit=&mode=` | Network or catalog search |
| `GET` | `/v1/assets/:provider/:asset` | Asset details and variants |
| `GET` | `/v1/assets/:provider/:asset/variants` | Variant list |
| `POST` | `/v1/assets/:provider/:asset/plan` | Validate and preview a download |
| `POST` | `/v1/downloads` | Import one asset |
| `POST` | `/v1/downloads/batch` | Import up to 20 assets |
| `GET` | `/v1/imports` | Local imports |
| `GET` | `/v1/credits/:provider/:asset?variant=` | Imported credit record |
| `GET` | `/v1/stats` | Catalog counts |
| `GET` | `/v1/review` | Assets needing license review |
| `POST` | `/v1/providers/:provider/check` | Explicit provider connectivity check |

Request bodies are JSON objects. Search queries are bounded per provider; changing filters or pages reuses cached metadata.

## TypeScript API

```ts
import { createLibrary } from "asset-library";

const library = await createLibrary();
try {
  const result = await library.search({
    query: "brick",
    category: "material",
    providers: ["polyhaven"],
    limit: 10
  });

  const asset = result.assets[0];
  if (asset) {
    const planned = await library.planDownload(asset.provider_id, asset.id, "1k");
    console.log(planned.plan.kind, planned.warnings);

    const imported = await library.download(asset.provider_id, asset.id, "1k");
    console.log(imported.folder, imported.files);
  }
} finally {
  await library.close();
}
```

An asset must first appear in search results or the local catalog before it can be detailed, planned, or downloaded. `planDownload` and `download` run the same policy checks; blocked licenses and paid assets are refused.

## License and download policy

- Only confirmed-free, zero-credit assets are imported.
- Non-commercial, no-derivatives, proprietary, editorial, paid, and otherwise restricted licenses are blocked.
- Unknown licenses are marked for review rather than described as free.
- Missing creators are recorded as `not supplied`; they are never invented.
- Downloads validate provider identity, variant IDs, filenames, URLs, and byte limits.
- Existing complete folders are reused, not overwritten.

## Data layout

The default data directory is `~/.local/share/asset-library`:

```text
assets.json                 normalized search catalog
imports/imports.json        completed import index
cache/                      HTTP response cache
library/<provider>/<title>_<hash>/...
```

Each imported variant contains:

```text
provenance.json
asset.credits.json
import_receipt.json
material.json               for materials
files.json                  for file bundles
_source/                    downloaded files
```

Material imports place a `.gdignore` in `_source/` so Godot does not import payload files directly.

## Configuration

| Variable | Purpose |
| --- | --- |
| `ASSET_LIBRARY_HOME` | Data directory |
| `ASSET_LIBRARY_OUTPUT` | Download output directory |
| `ASSET_LIBRARY_PROVIDERS` | Comma-separated enabled provider IDs |
| `ASSET_LIBRARY_DISABLED_PROVIDERS` | Comma-separated disabled provider IDs |
| `ASSET_LIBRARY_PROVIDER_DIRS` | Additional provider module directories |
| `ASSET_LIBRARY_OFFLINE=1` | Fail instead of making network requests |
| `ASSET_LIBRARY_TOKEN` | HTTP bearer token |
| `ASSET_LIBRARY_HOST`, `ASSET_LIBRARY_PORT` | HTTP bind address |
| `ASSET_LIBRARY_CORS` | Allowed CORS origin |
| `3DTEXEL_API_KEY`, `TEXEL_API_KEY`, `TEXEL` | Texel API key |

API keys are read only from the inherited environment. They are never written to the catalog, cache, receipts, or logs.

## Testing

All automated provider tests are offline and use checked-in fixtures:

```bash
npm test
npm run typecheck
npm run typecheck:test
```

Tests cover provider contracts, search/plan/download/catalog behavior, HTTP authentication, MCP stdio, and CLI startup. Live provider requests are not part of the test suite.

## License

MIT. Provider metadata and downloaded assets remain subject to their own licenses and attribution requirements. See `../ATTRIBUTION.md`.
