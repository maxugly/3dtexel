#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { createLibrary, type AssetLibrary } from "./index.js";
import { redactMessage } from "./util/sanitize.js";

const categories = z.enum(["all", "material", "model", "audio", "image"]);
const mode = z.enum(["network", "catalog"]);

function text(value: unknown): { content: Array<{ type: "text"; text: string }> } {
  return {
    content: [{ type: "text", text: JSON.stringify(value, null, 2) }]
  };
}

function failure(error: unknown): { isError: true; content: Array<{ type: "text"; text: string }> } {
  return {
    isError: true,
    content: [{
      type: "text",
      text: redactMessage(error instanceof Error ? error.message : String(error))
    }]
  };
}

function register(server: McpServer, library: AssetLibrary): void {
  server.registerTool("list_providers", {
    description: "List built-in and external asset providers with credentials and capabilities. Reads local configuration only; no network requests.",
    inputSchema: {}
  }, async () => {
    try {
      return text({ providers: await library.providers() });
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("search_assets", {
    description: "Search enabled asset providers. Network mode performs bounded provider searches; catalog mode only queries the local cached catalog. Images, textures, models, and audio are supported.",
    inputSchema: {
      query: z.string().optional().describe("Search terms. Empty searches may return catalog or featured results depending on provider."),
      category: categories.optional(),
      providers: z.array(z.string()).optional().describe("Provider IDs to query. Defaults to all enabled providers."),
      limit: z.number().int().min(1).max(100).optional(),
      free_only: z.boolean().optional(),
      license: z.string().optional().describe("Case-insensitive license text filter."),
      mode: mode.optional().describe("network (default) or catalog"),
      refresh: z.boolean().optional().describe("Bypass the ten-minute search cache.")
    }
  }, async (args) => {
    try {
      return text(await library.search({
        query: args.query,
        category: args.category,
        providers: args.providers,
        limit: args.limit,
        free_only: args.free_only,
        license: args.license,
        mode: args.mode,
        refresh: args.refresh
      }));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("get_asset", {
    description: "Load one catalog asset and resolve provider details when needed. The asset must first appear in search results or the local catalog.",
    inputSchema: {
      provider_id: z.string(),
      asset_id: z.string(),
      refresh: z.boolean().optional()
    }
  }, async (args) => {
    try {
      return text(await library.getAsset(args.provider_id, args.asset_id, { refresh: args.refresh }));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("list_variants", {
    description: "List downloadable variants (resolution, format, or source files) for a catalog asset, resolving provider details first when needed.",
    inputSchema: {
      provider_id: z.string(),
      asset_id: z.string(),
      refresh: z.boolean().optional()
    }
  }, async (args) => {
    try {
      return text(await library.variants(args.provider_id, args.asset_id, { refresh: args.refresh }));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("plan_download", {
    description: "Validate license and entitlement and show a download plan without writing files. Providers that issue transient URLs at download time return an empty map preview.",
    inputSchema: {
      provider_id: z.string(),
      asset_id: z.string(),
      variant: z.string().optional().describe("Variant ID from list_variants. Defaults to the first variant.")
    }
  }, async (args) => {
    try {
      return text(await library.planDownload(args.provider_id, args.asset_id, args.variant));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("download_asset", {
    description: "Download one confirmed-free, zero-credit asset variant into the local library. Refuses blocked licenses, paid assets, unsafe filenames, and existing completed folders. Preserves credits and provenance sidecars.",
    inputSchema: {
      provider_id: z.string(),
      asset_id: z.string(),
      variant: z.string().optional()
    }
  }, async (args) => {
    try {
      return text(await library.download(args.provider_id, args.asset_id, args.variant));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("download_assets", {
    description: "Download up to 20 asset variants sequentially into the local library. Each result reports success or an error independently.",
    inputSchema: {
      jobs: z.array(z.object({
        provider_id: z.string(),
        asset_id: z.string(),
        variant: z.string().optional()
      })).min(1).max(20)
    }
  }, async (args) => {
    try {
      return text(await library.downloadMany(args.jobs.map((job) => ({
        provider_id: job.provider_id,
        asset_id: job.asset_id,
        variant: job.variant ?? ""
      }))));
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("list_imports", {
    description: "List local import receipts and verify that recorded files still exist. Does not contact providers.",
    inputSchema: {
      provider_id: z.string().optional(),
      asset_id: z.string().optional()
    }
  }, async (args) => {
    try {
      return text({ imports: await library.imports(args) });
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("get_credits", {
    description: "Read the preserved credit record for a completed local import.",
    inputSchema: {
      provider_id: z.string(),
      asset_id: z.string(),
      variant: z.string().optional()
    }
  }, async (args) => {
    try {
      return text({ credits: await library.credits(args.provider_id, args.asset_id, args.variant) });
    } catch (error) {
      return failure(error);
    }
  });

  server.registerTool("check_provider", {
    description: "Explicitly check provider connectivity and credentials. This may make one bounded network request.",
    inputSchema: {
      provider_id: z.string()
    }
  }, async (args) => {
    try {
      return text(await library.checkProvider(args.provider_id));
    } catch (error) {
      return failure(error);
    }
  });
}

async function main(): Promise<void> {
  const library = await createLibrary();
  const server = new McpServer({
    name: "asset-library",
    version: "0.1.0"
  });
  register(server, library);
  const transport = new StdioServerTransport();
  const shutdown = async () => {
    await server.close().catch(() => undefined);
    await library.close().catch(() => undefined);
  };
  process.once("SIGINT", () => { void shutdown().finally(() => process.exit(0)); });
  process.once("SIGTERM", () => { void shutdown().finally(() => process.exit(0)); });
  await server.connect(transport);
}

main().catch((error: unknown) => {
  process.stderr.write(`asset-library MCP failed: ${redactMessage(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
});
