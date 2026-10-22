#!/usr/bin/env node
import { createLibrary, type LibraryOptions } from "./index.js";
import { startHttpServer } from "./http-server.js";
import type { AssetCategory } from "./types.js";
import { redactMessage } from "./util/sanitize.js";

interface Parsed {
  command: string;
  positionals: string[];
  options: Map<string, string | true>;
}

const VALUE_OPTIONS = new Set([
  "provider", "providers", "category", "limit", "variant", "license", "mode",
  "home", "output", "host", "port", "token"
]);

function parse(argv: string[]): Parsed {
  const [command = "help", ...rest] = argv;
  const positionals: string[] = [];
  const options = new Map<string, string | true>();
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index]!;
    if (!token.startsWith("--")) {
      positionals.push(token);
      continue;
    }
    const [rawName, inline] = token.slice(2).split("=", 2);
    const name = rawName === "free-only" ? "free" : rawName;
    if (inline !== undefined) {
      options.set(name, inline);
    } else if (VALUE_OPTIONS.has(name)) {
      const value = rest[index + 1];
      if (!value || value.startsWith("--")) {
        throw new Error(`Option --${name} requires a value.`);
      }
      options.set(name, value);
      index += 1;
    } else {
      options.set(name, true);
    }
  }
  return { command, positionals, options };
}

function stringOption(parsed: Parsed, name: string): string | undefined {
  const value = parsed.options.get(name);
  return typeof value === "string" ? value : undefined;
}

function flag(parsed: Parsed, name: string): boolean {
  return parsed.options.get(name) === true || parsed.options.get(name) === "true";
}

function ref(parsed: Parsed): { provider: string; asset: string } {
  const first = parsed.positionals[0] ?? "";
  const separator = first.indexOf(":");
  if (separator > 0 && separator < first.length - 1) {
    return { provider: first.slice(0, separator), asset: first.slice(separator + 1) };
  }
  const provider = stringOption(parsed, "provider") ?? parsed.positionals[0];
  const asset = parsed.positionals[1];
  if (!provider || !asset) {
    throw new Error("Provide an asset as provider:asset_id, or pass the provider and asset ID as two arguments.");
  }
  return { provider, asset };
}

function libraryOptions(parsed: Parsed): LibraryOptions {
  return {
    home: stringOption(parsed, "home"),
    output: stringOption(parsed, "output"),
    offline: flag(parsed, "offline")
  };
}

function humanSearch(result: Awaited<ReturnType<Awaited<ReturnType<typeof createLibrary>>["search"]>>): string {
  const lines: string[] = [];
  for (const asset of result.assets) {
    const authors = asset.authors.map((author) => author.name).join(", ") || "creator not supplied";
    lines.push(`${asset.provider_id}:${asset.id}`);
    lines.push(`  ${asset.title} · ${asset.type} · ${asset.license.name}`);
    lines.push(`  ${authors} · ${asset.price.free ? "free" : "paid"} · ${asset.variants.length} variants`);
    if (asset.url) {
      lines.push(`  ${asset.url}`);
    }
  }
  if (!lines.length) {
    lines.push("No assets found.");
  }
  for (const error of result.errors) {
    lines.push(`Warning (${error.provider_id}): ${error.message}`);
  }
  return lines.join("\n");
}

function printJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

async function main(): Promise<void> {
  const parsed = parse(process.argv.slice(2));
  if (parsed.command === "help" || parsed.command === "--help" || parsed.command === "-h") {
    process.stdout.write(`asset-library 0.1.0

Usage:
  asset-library providers [--json]
  asset-library search [query] [--providers a,b] [--category material|model|audio|image|all]
                        [--limit 24] [--free] [--license cc0] [--mode network|catalog] [--json]
  asset-library get provider:asset [--refresh] [--json]
  asset-library variants provider:asset [--refresh] [--json]
  asset-library plan provider:asset [--variant 2k] [--json]
  asset-library download provider:asset [--variant 2k] [--json]
  asset-library imports [--provider id] [--asset id] [--json]
  asset-library credits provider:asset [--variant 2k] [--json]
  asset-library check provider [--json]
  asset-library stats [--json]
  asset-library review [--json]
  asset-library serve [--host 127.0.0.1] [--port 7575] [--token ...]

Environment:
  ASSET_LIBRARY_HOME, ASSET_LIBRARY_OUTPUT, ASSET_LIBRARY_PROVIDERS,
  ASSET_LIBRARY_DISABLED_PROVIDERS, ASSET_LIBRARY_TOKEN, ASSET_LIBRARY_OFFLINE,
  TEXEL_API_KEY or 3DTEXEL_API_KEY.
`);
    return;
  }

  const library = await createLibrary({
    ...libraryOptions(parsed),
    offline: flag(parsed, "offline")
  });
  try {
    switch (parsed.command) {
      case "providers": {
        const providers = await library.providers();
        if (flag(parsed, "json")) {
          printJson({ providers });
        } else {
          for (const provider of providers) {
            process.stdout.write(`${provider.id.padEnd(14)} ${provider.enabled ? "enabled " : "disabled"} ${provider.credentials.padEnd(18)} ${provider.capabilities.join(",")}\n`);
          }
        }
        return;
      }
      case "search": {
        const result = await library.search({
          query: parsed.positionals.join(" "),
          category: (stringOption(parsed, "category") as AssetCategory | undefined) ?? "all",
          providers: stringOption(parsed, "providers")?.split(",").map((entry) => entry.trim()).filter(Boolean),
          limit: stringOption(parsed, "limit") ? Number(stringOption(parsed, "limit")) : undefined,
          free_only: flag(parsed, "free"),
          license: stringOption(parsed, "license"),
          mode: (stringOption(parsed, "mode") as "network" | "catalog" | undefined) ?? "network",
          refresh: flag(parsed, "refresh")
        });
        if (flag(parsed, "json")) {
          printJson(result);
        } else {
          process.stdout.write(`${humanSearch(result)}\n`);
        }
        return;
      }
      case "get":
      case "asset": {
        const target = ref(parsed);
        const result = await library.getAsset(target.provider, target.asset, { refresh: flag(parsed, "refresh") });
        if (flag(parsed, "json")) {
          printJson(result);
        } else {
          process.stdout.write(`${result.asset.title}\n${result.asset.provider_id}:${result.asset.id}\n${result.asset.url}\nVariants: ${result.variants.map((variant) => variant.id).join(", ") || "none"}\n`);
        }
        return;
      }
      case "variants": {
        const target = ref(parsed);
        const result = await library.variants(target.provider, target.asset, { refresh: flag(parsed, "refresh") });
        if (flag(parsed, "json")) {
          printJson(result);
        } else {
          for (const variant of result.variants) {
            process.stdout.write(`${variant.id}\t${variant.label}\t${variant.kind}\t${variant.resolution ?? ""}\t${variant.format ?? ""}\n`);
          }
        }
        return;
      }
      case "plan": {
        const target = ref(parsed);
        const result = await library.planDownload(target.provider, target.asset, stringOption(parsed, "variant"));
        printJson(result);
        return;
      }
      case "download": {
        const target = ref(parsed);
        const result = await library.download(target.provider, target.asset, stringOption(parsed, "variant"));
        if (flag(parsed, "json")) {
          printJson(result);
        } else {
          process.stdout.write(`${result.reused ? "Reused" : "Imported"} ${result.folder}\n`);
          for (const warning of result.warnings) {
            process.stdout.write(`Warning: ${warning}\n`);
          }
        }
        return;
      }
      case "imports": {
        const imports = await library.imports({
          provider_id: stringOption(parsed, "provider"),
          asset_id: stringOption(parsed, "asset")
        });
        if (flag(parsed, "json")) {
          printJson({ imports });
        } else {
          for (const record of imports) {
            process.stdout.write(`${record.key}\t${record.variant}\t${record.exists ? "complete" : `missing:${record.missing.join(",")}`}\t${record.folder}\n`);
          }
        }
        return;
      }
      case "credits": {
        const target = ref(parsed);
        printJson({ credits: await library.credits(target.provider, target.asset, stringOption(parsed, "variant")) });
        return;
      }
      case "check": {
        const provider = parsed.positionals[0] ?? stringOption(parsed, "provider");
        if (!provider) {
          throw new Error("Provide a provider ID.");
        }
        const result = await library.checkProvider(provider);
        if (flag(parsed, "json")) {
          printJson(result);
        } else {
          process.stdout.write(`${result.ok ? "OK" : "FAILED"} ${provider}: ${result.message}\n`);
        }
        if (!result.ok) {
          process.exitCode = 1;
        }
        return;
      }
      case "stats": {
        printJson({ catalog: library.catalogStats() });
        return;
      }
      case "review": {
        if (flag(parsed, "json")) {
          printJson({ assets: library.reviewQueue() });
        } else {
          for (const asset of library.reviewQueue()) {
            process.stdout.write(`${asset.provider_id}:${asset.id}\t${asset.title}\t${asset.license.name}\n`);
          }
        }
        return;
      }
      case "serve": {
        const host = stringOption(parsed, "host");
        const port = stringOption(parsed, "port") ? Number(stringOption(parsed, "port")) : undefined;
        if (host) {
          library.config.http_host = host;
        }
        if (port) {
          library.config.http_port = port;
        }
        if (stringOption(parsed, "token")) {
          library.config.http_token = stringOption(parsed, "token");
        }
        const running = await startHttpServer(library, { host, port });
        process.stderr.write(`asset-library HTTP listening on ${running.url}\n`);
        await new Promise<void>((resolve) => {
          const shutdown = () => resolve();
          process.once("SIGINT", shutdown);
          process.once("SIGTERM", shutdown);
        });
        await running.close();
        return;
      }
      default:
        throw new Error(`Unknown command: ${parsed.command}. Run asset-library help.`);
    }
  } finally {
    await library.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`${redactMessage(error instanceof Error ? error.message : String(error))}\n`);
  process.exit(1);
});
