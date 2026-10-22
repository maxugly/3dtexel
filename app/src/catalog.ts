import path from "node:path";
import { publicAsset } from "./asset.js";
import { evaluateLicense, LICENSE_STATUS } from "./license.js";
import type { Asset, AssetCategory } from "./types.js";
import { readJson, writeJsonAtomic } from "./util/fs.js";

interface CatalogFile {
  schema_version: 1;
  updated_utc?: string;
  assets: Record<string, Asset>;
}

export interface CatalogQuery {
  query?: string;
  category?: AssetCategory;
  limit?: number;
  free_only?: boolean;
  license?: string;
  providers?: string[];
}

export interface CatalogStats {
  assets: number;
  by_provider: Record<string, number>;
  by_type: Record<string, number>;
}

export function qualifiedKey(providerId: string, assetId: string): string {
  return `${providerId}:${assetId}`;
}

function normalizeQuery(value: string): string[] {
  return value
    .toLowerCase()
    .split(/\s+/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function scoreAsset(asset: Asset, terms: string[]): number {
  if (!terms.length) {
    return 1;
  }
  const title = asset.title.toLowerCase();
  const id = asset.id.toLowerCase();
  const tags = asset.tags.join(" ").toLowerCase();
  const categories = asset.categories.join(" ").toLowerCase();
  let score = 0;
  for (const term of terms) {
    if (title === term || id === term) {
      score += 12;
    } else if (title.startsWith(term) || id.startsWith(term)) {
      score += 8;
    } else if (title.includes(term) || id.includes(term)) {
      score += 5;
    } else if (tags.includes(term)) {
      score += 3;
    } else if (categories.includes(term)) {
      score += 2;
    } else {
      return 0;
    }
  }
  return score;
}

export class Catalog {
  readonly file: string;
  private assets = new Map<string, Asset>();
  private dirty = false;
  private loaded = false;

  constructor(file: string) {
    this.file = path.resolve(file);
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const data = await readJson<CatalogFile>(this.file);
    if (data) {
      if (data.schema_version !== 1 || typeof data.assets !== "object" || data.assets === null) {
        throw new Error(`Unsupported catalog format in ${this.file}`);
      }
      for (const [key, asset] of Object.entries(data.assets)) {
        if (asset && typeof asset === "object" && asset.provider_id && asset.id) {
          this.assets.set(key, publicAsset(asset));
        }
      }
    }
    this.loaded = true;
  }

  get size(): number {
    return this.assets.size;
  }

  get(providerId: string, assetId: string): Asset | undefined {
    return this.assets.get(qualifiedKey(providerId, assetId));
  }

  getByKey(key: string): Asset | undefined {
    return this.assets.get(key);
  }

  upsert(asset: Asset): void {
    if (!asset.provider_id || !asset.id) {
      throw new Error("Catalog assets require a provider and asset ID.");
    }
    this.assets.set(qualifiedKey(asset.provider_id, asset.id), publicAsset(asset));
    this.dirty = true;
  }

  upsertMany(assets: Asset[]): void {
    for (const asset of assets) {
      this.upsert(asset);
    }
  }

  remove(providerId: string, assetId: string): boolean {
    const removed = this.assets.delete(qualifiedKey(providerId, assetId));
    this.dirty = this.dirty || removed;
    return removed;
  }

  all(): Asset[] {
    return [...this.assets.values()];
  }

  search(query: CatalogQuery = {}): Asset[] {
    const terms = normalizeQuery(query.query ?? "");
    const category = query.category ?? "all";
    const providers = query.providers ? new Set(query.providers) : null;
    const license = query.license?.toLowerCase();
    const limit = Math.max(0, Math.min(query.limit ?? 100, 1000));
    const scored: Array<{ asset: Asset; score: number }> = [];
    for (const asset of this.assets.values()) {
      if (category !== "all" && asset.type !== category) {
        continue;
      }
      if (providers && !providers.has(asset.provider_id)) {
        continue;
      }
      if (query.free_only && !asset.price.free) {
        continue;
      }
      if (license) {
        const names = [asset.license.id, asset.license.name, ...(asset.licenses ?? []).flatMap((entry) => [entry.id, entry.name])]
          .filter(Boolean)
          .join(" ")
          .toLowerCase();
        if (!names.includes(license)) {
          continue;
        }
      }
      const score = scoreAsset(asset, terms);
      if (score > 0) {
        scored.push({ asset, score });
      }
    }
    scored.sort((left, right) => right.score - left.score || left.asset.title.localeCompare(right.asset.title));
    return scored.slice(0, limit).map((entry) => entry.asset);
  }

  stats(): CatalogStats {
    const byProvider: Record<string, number> = {};
    const byType: Record<string, number> = {};
    for (const asset of this.assets.values()) {
      byProvider[asset.provider_id] = (byProvider[asset.provider_id] ?? 0) + 1;
      byType[asset.type] = (byType[asset.type] ?? 0) + 1;
    }
    return { assets: this.assets.size, by_provider: byProvider, by_type: byType };
  }

  reviewQueue(): Asset[] {
    return this.all().filter((asset) => evaluateLicense(asset).status >= LICENSE_STATUS.UNKNOWN);
  }

  async flush(force = false): Promise<void> {
    if (!this.dirty && !force) {
      return;
    }
    const assets: Record<string, Asset> = {};
    for (const [key, asset] of [...this.assets.entries()].sort(([left], [right]) => left.localeCompare(right))) {
      assets[key] = asset;
    }
    await writeJsonAtomic(this.file, {
      schema_version: 1,
      updated_utc: new Date().toISOString(),
      assets
    } satisfies CatalogFile);
    this.dirty = false;
  }
}
