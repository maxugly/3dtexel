import path from "node:path";
import { Catalog } from "./catalog.js";
import type { RuntimeConfig, RuntimeConfigInput } from "./config.js";
import { resolveConfig } from "./config.js";
import { DownloadService, type DownloadPlanResult } from "./download.js";
import { HttpClient } from "./http-client.js";
import { Inventory, type InventoryEntry } from "./inventory.js";
import { ProviderRegistry } from "./registry.js";
import { SearchService, type SearchOptions } from "./search.js";
import type {
  Asset,
  AssetVariant,
  DownloadManyResult,
  HttpTransport,
  ImportJob,
  ImportRecord,
  ImportResult,
  ProviderStatus,
  SearchResponse
} from "./types.js";
import { readJson, slug } from "./util/fs.js";

export interface LibraryOptions extends RuntimeConfigInput {
  env?: Record<string, string | undefined>;
  http?: HttpTransport;
  now?: () => Date;
}

export interface AssetDetail {
  asset: Asset;
  variants: AssetVariant[];
}

export interface ProviderCheck {
  provider_id: string;
  ok: boolean;
  message: string;
}

export class AssetLibrary {
  readonly config: RuntimeConfig;
  readonly catalog: Catalog;
  readonly inventory: Inventory;
  readonly registry: ProviderRegistry;
  readonly http: HttpTransport;
  readonly downloads: DownloadService;
  private readonly searchService: SearchService;
  private readonly now: () => Date;

  private constructor(options: LibraryOptions, config: RuntimeConfig) {
    this.config = config;
    this.now = options.now ?? (() => new Date());
    this.http = options.http ?? new HttpClient({
      cacheDir: config.cache,
      offline: config.offline,
      timeoutMs: config.request_timeout_ms,
      maxBytes: 32 * 1024 * 1024,
      minIntervalMs: config.min_request_interval_ms,
      userAgent: config.user_agent
    });
    this.catalog = new Catalog(config.catalog_file);
    this.inventory = new Inventory(config.inventory_file);
    this.registry = new ProviderRegistry({
      config,
      http: this.http,
      env: options.env ?? process.env
    });
    this.searchService = new SearchService(this.catalog, this.registry);
    this.downloads = new DownloadService({
      config,
      catalog: this.catalog,
      registry: this.registry,
      http: this.http,
      inventory: this.inventory,
      now: this.now
    });
  }

  static async create(options: LibraryOptions = {}): Promise<AssetLibrary> {
    const config = resolveConfig(options);
    const library = new AssetLibrary(options, config);
    await library.catalog.load();
    await library.inventory.load();
    if (config.provider_dirs.length) {
      await library.registry.loadExternal(config.provider_dirs);
    }
    return library;
  }

  async search(options: SearchOptions = {}): Promise<SearchResponse> {
    return this.searchService.search(options);
  }

  async providers(): Promise<ProviderStatus[]> {
    return this.registry.statuses();
  }

  async checkProvider(providerId: string, signal?: AbortSignal): Promise<ProviderCheck> {
    const provider = this.registry.get(providerId);
    if (!this.registry.isEnabled(providerId)) {
      return { provider_id: providerId, ok: false, message: "Provider is disabled." };
    }
    if (!provider.checkConnection) {
      return { provider_id: providerId, ok: true, message: "Provider does not expose a connection check." };
    }
    try {
      const result = await provider.checkConnection({ signal });
      return { provider_id: providerId, ...result };
    } catch (error) {
      return {
        provider_id: providerId,
        ok: false,
        message: error instanceof Error ? error.message : String(error)
      };
    }
  }

  async getAsset(providerId: string, assetId: string, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<AssetDetail> {
    const provider = this.registry.get(providerId);
    if (!this.registry.isEnabled(providerId)) {
      throw new Error(`Provider is disabled: ${providerId}`);
    }
    const stored = this.catalog.get(providerId, assetId);
    if (!stored) {
      throw new Error(`Asset ${providerId}:${assetId} is not in the local catalog. Search for it first.`);
    }
    let asset = stored;
    if (options.refresh || !provider.isDetailed(stored)) {
      asset = await provider.details(stored, { refresh: options.refresh, signal: options.signal });
      if (asset.provider_id !== stored.provider_id || asset.id !== stored.id) {
        throw new Error("The provider returned a different asset identity; details were not saved.");
      }
      this.catalog.upsert(asset);
      await this.catalog.flush();
    }
    return { asset, variants: provider.variants(asset) };
  }

  async variants(providerId: string, assetId: string, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<AssetDetail> {
    return this.getAsset(providerId, assetId, options);
  }

  async planDownload(providerId: string, assetId: string, variant?: string, signal?: AbortSignal): Promise<DownloadPlanResult> {
    return this.downloads.plan(providerId, assetId, variant, signal);
  }

  async download(providerId: string, assetId: string, variant?: string, signal?: AbortSignal): Promise<ImportResult> {
    const result = await this.downloads.download(providerId, assetId, variant, signal);
    await this.inventory.flush();
    return result;
  }

  async downloadMany(jobs: ImportJob[], signal?: AbortSignal): Promise<DownloadManyResult> {
    if (!jobs.length) {
      throw new Error("At least one download job is required.");
    }
    if (jobs.length > 20) {
      throw new Error("At most 20 download jobs are allowed per request.");
    }
    const result = await this.downloads.downloadMany(jobs, signal);
    await this.inventory.flush();
    return result;
  }

  async imports(filter: { provider_id?: string; asset_id?: string } = {}): Promise<InventoryEntry[]> {
    return this.inventory.list(filter);
  }

  async credits(providerId: string, assetId: string, variant?: string): Promise<Record<string, unknown>> {
    const record = variant
      ? this.inventory.find(providerId, assetId, slug(variant), this.config.output)
      : this.inventory.findAny(providerId, assetId, this.config.output);
    if (!record) {
      throw new Error(`No completed import for ${providerId}:${assetId}${variant ? ` variant ${variant}` : ""}.`);
    }
    const sidecar = path.join(record.folder, "asset.credits.json");
    const value = await readJson<Record<string, unknown>>(sidecar);
    if (!value) {
      throw new Error(`The import receipt exists but its credits sidecar is missing: ${sidecar}`);
    }
    return value;
  }

  catalogStats(): ReturnType<Catalog["stats"]> {
    return this.catalog.stats();
  }

  reviewQueue(): Asset[] {
    return this.catalog.reviewQueue();
  }

  async close(): Promise<void> {
    await this.catalog.flush();
    await this.inventory.flush();
  }
}

export async function createLibrary(options: LibraryOptions = {}): Promise<AssetLibrary> {
  return AssetLibrary.create(options);
}

export type {
  Asset,
  AssetDetail as AssetDetails,
  AssetVariant,
  DownloadManyResult,
  ImportJob,
  ImportRecord,
  ImportResult,
  ProviderStatus,
  SearchOptions,
  SearchResponse
};

export { DownloadService } from "./download.js";
export { Catalog } from "./catalog.js";
export { Inventory } from "./inventory.js";
export { ProviderRegistry } from "./registry.js";
export { SearchService } from "./search.js";
export { resolveConfig } from "./config.js";
