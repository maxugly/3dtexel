# Blend Swap Provider for 3DTexel

Integrates Blend Swap's community repository of Blender 3D models into the Godot 4+ Asset Library.

## Features
- **Blender 3D Models**: Community-created `.blend` files covering characters, props, architecture, vehicles, and environments.
- **Dual Mode**:
  - **Official REST API & MCP**: When configured with `BLENDSWAP_KEY` or `BLENDSWAP_API_KEY`, uses the official v1 REST API (`https://blendswap.com/api/v1/assets` and `https://blendswap.com/api/v1/downloads`).
  - **Public Web Fallback**: Allows search and metadata discovery without requiring an API key.
- **Zero-Credit Guardrail**: Strictly verifies that downloads cost zero credits (`charged: false` and `credits_spent: 0`), using the shared daily free allowance or free community downloads. Paid credit deductions are rejected.
- **Licensing Compliance**:
  - Supports CC0 1.0 Universal (`Policy.Status.PERMISSIVE`).
  - Supports CC-BY 3.0/4.0 (`Policy.Status.ATTRIBUTION`).
  - Blocks NC (Non-Commercial) and ND licenses per project policy.
- **Offline & Safe**: Full offline test suite with synthetic fixtures; never stores secret API keys or bearer tokens in public metadata sidecars.
