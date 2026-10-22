import type { Catalog } from "./catalog.js";
import type { ProviderRegistry } from "./registry.js";
import type {
  Asset,
  AssetCategory,
  SearchError,
  SearchResponse,
  SearchPage
} from "./types.js";
import { publicAsset } from "./asset.js";
import { qualifiedKey } from "./catalog.js";

interface SearchCacheEntry {
  items: Asset[];
  cursor: string | null;
  updated_at: number;
}

export interface SearchOptions {
  query?: string;
  category?: AssetCategory;
  providers?: string[];
  limit?: number;
  free_only?: boolean;
  license?: string;
  refresh?: boolean;
  mode?: "network" | "catalog";
  signal?: AbortSignal;
}

function matchesQuery(asset: Asset, terms: string[]): boolean {
  if (!terms.length) {
    return true;
  }
  const haystack = [
    asset.id,
    asset.title,
    asset.description ?? "",
    asset.tags.join(" "),
    asset.categories.join(" ")
  ].join(" ").toLowerCase();
  return terms.every((term) => haystack.includes(term));
}

function matchesLicense(asset: Asset, license: string): boolean {
  const needle = license.toLowerCase();
  return [asset.license, ...(asset.licenses ?? [])]
    .some((entry) => `${entry.id ?? ""} ${entry.name}`.toLowerCase().includes(needle));
}

function message(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  return raw
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, "Bearer [redacted]")
    .replace(/([?&](?:api[_-]?key|token|key|signature|sig)=)[^&\s]+/gi, "$1[redacted]")
    .slice(0, 300);
}

export class SearchService {
  private readonly catalog: Catalog;
  private readonly registry: ProviderRegistry;
  private readonly cache = new Map<string, SearchCacheEntry>();
  private readonly ttlMs = 7 * 24 * 60 * 60 * 1000;

  constructor(catalog: Catalog, registry: ProviderRegistry) {
    this.catalog = catalog;
    this.registry = registry;
  }

  clearCache(): void {
    this.cache.clear();
  }

  async search(options: SearchOptions = {}): Promise<SearchResponse> {
    const query = (options.query ?? "").trim();
    const category = options.category ?? "all";
    const limit = Math.max(1, Math.min(options.limit ?? 24, 100));
    const terms = query.toLowerCase().split(/\s+/).filter(Boolean);
    const selected = this.registry.selected(options.providers);
    if (!selected.length) {
      throw new Error("No enabled providers match the request.");
    }
    if (options.mode === "catalog") {
      return {
        assets: this.catalog.search({
          query,
          category,
          limit,
          free_only: options.free_only,
          license: options.license,
          providers: selected.map((provider) => provider.descriptor().id)
        }),
        errors: [],
        providers: selected.map((provider) => provider.descriptor().id)
      };
    }

    const target = selected.length === 1 ? limit : Math.max(6, Math.ceil(limit / selected.length));
    const errors: SearchError[] = [];
    const collected = await Promise.all(selected.map(async (provider) => {
      const descriptor = provider.descriptor();
      try {
        const items = await this.collect(
          descriptor.id,
          provider,
          query,
          category,
          target,
          Boolean(options.refresh),
          options.signal
        );
        const filtered = items.filter((asset) =>
          matchesQuery(asset, terms)
          && (category === "all" || asset.type === category)
          && (!options.free_only || asset.price.free)
          && (!options.license || matchesLicense(asset, options.license))
        ).map(publicAsset);
        this.catalog.upsertMany(items);
        return filtered;
      } catch (error) {
        errors.push({ provider_id: descriptor.id, message: message(error) });
        return [];
      }
    }));
    await this.catalog.flush();

    const assets: Asset[] = [];
    const seen = new Set<string>();
    let index = 0;
    while (assets.length < limit) {
      let added = false;
      for (const list of collected) {
        const asset = list[index];
        if (asset) {
          const key = qualifiedKey(asset.provider_id, asset.id);
          if (!seen.has(key)) {
            seen.add(key);
            assets.push(asset);
            added = true;
            if (assets.length >= limit) {
              break;
            }
          }
        }
      }
      if (!added) {
        break;
      }
      index += 1;
    }

    return {
      assets,
      errors,
      providers: selected.map((provider) => provider.descriptor().id)
    };
  }

  private async collect(
    providerId: string,
    provider: ReturnType<ProviderRegistry["get"]>,
    query: string,
    category: AssetCategory,
    target: number,
    refresh: boolean,
    signal?: AbortSignal
  ): Promise<Asset[]> {
    const key = `${providerId}\u0000${category}\u0000${query.toLowerCase()}`;
    const existing = this.cache.get(key);
    let entry = refresh || !existing || Date.now() - existing.updated_at > this.ttlMs
      ? { items: [], cursor: null as string | null, updated_at: Date.now() }
      : existing;
    if (refresh) {
      this.cache.delete(key);
    }

    let pages = 0;
    while (entry.items.length < target && (entry.items.length === 0 || entry.cursor) && pages < 4) {
      const page: SearchPage = await provider.search({
        query,
        category,
        cursor: entry.cursor,
        limit: target,
        refresh: refresh && pages === 0,
        signal
      });
      const known = new Set(entry.items.map((asset) => asset.id));
      for (const asset of page.items) {
        if (!known.has(asset.id)) {
          known.add(asset.id);
          entry.items.push(asset);
        }
      }
      entry.cursor = page.next_cursor;
      entry.updated_at = Date.now();
      pages += 1;
      if (!page.items.length) {
        break;
      }
    }
    this.cache.set(key, entry);
    return entry.items;
  }
}
