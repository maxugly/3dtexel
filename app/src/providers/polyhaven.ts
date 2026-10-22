import { createAsset, mergeAsset, normalizeAssetType } from "../asset.js";
import type {
  Asset,
  AssetType,
  AssetVariant,
  DownloadPlan,
  FilesPlan,
  MaterialPlan,
  MaterialRole,
  MaterialSource,
  Provider,
  ProviderContext,
  ProviderDescriptor,
  SearchPage,
  SearchParams,
  SourceFile
} from "../types.js";
import { canDownload, fileFromUrl, matchesText, pageSlice, variant } from "./helpers.js";
import { slug } from "../util/fs.js";
import { sanitizeRecord } from "../util/sanitize.js";

const API = "https://api.polyhaven.com";
const PAGE_SIZE = 30;

interface RawAsset extends Record<string, unknown> {
  id?: string;
  name?: string;
  type?: number | string;
  categories?: string[];
  tags?: string[];
  authors?: Record<string, string> | string[];
  download_count?: number;
}

const MAP_ROLES: Record<string, MaterialRole> = {
  diff: "albedo",
  diffuse: "albedo",
  albedo: "albedo",
  basecolor: "albedo",
  nor_gl: "normal",
  nor_dx: "normal",
  normal: "normal",
  rough: "roughness",
  roughness: "roughness",
  metal: "metallic",
  metalness: "metallic",
  metallic: "metallic",
  ao: "ao",
  displacement: "height",
  disp: "height",
  height: "height",
  opacity: "opacity",
  emission: "emission"
};

function assetType(raw: RawAsset): AssetType {
  const value = raw.type;
  if (value === 0 || value === "0") {
    return "image";
  }
  if (value === 2 || value === "2") {
    return "model";
  }
  if (typeof value === "string") {
    return normalizeAssetType(value);
  }
  return "material";
}

function mappedRole(name: string): MaterialRole | undefined {
  return MAP_ROLES[name.toLowerCase()];
}

function mapSource(value: unknown): MaterialSource | undefined {
  if (typeof value === "string") {
    return value.startsWith("https://") ? { url: value } : undefined;
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const url = typeof record.url === "string" ? record.url : "";
    if (!url.startsWith("https://")) {
      return undefined;
    }
    return {
      url,
      filename: typeof record.filename === "string" ? record.filename : undefined,
      size: typeof record.size === "number" ? record.size : undefined
    };
  }
  return undefined;
}

export class PolyHavenProvider implements Provider {
  private readonly ctx: ProviderContext;

  constructor(context: ProviderContext) {
    this.ctx = context;
  }

  descriptor(): ProviderDescriptor {
    return {
      id: "polyhaven",
      name: "Poly Haven",
      website: "https://polyhaven.com/",
      key_env: [],
      capabilities: ["material", "model", "image"],
      description: "CC0 HDRIs, PBR materials, and models from Poly Haven."
    };
  }

  credentialStatus(): string {
    return "No key required.";
  }

  private normalize(raw: RawAsset, fetched: boolean): Asset {
    const id = String(raw.id ?? "");
    const authors = raw.authors;
    return createAsset({
      provider_id: "polyhaven",
      provider_name: "Poly Haven",
      id,
      title: String(raw.name ?? id),
      type: assetType(raw),
      url: `https://polyhaven.com/a/${id}`,
      thumbnail_url: `https://cdn.polyhaven.com/asset_img/thumbs/${id}.png?width=256&height=256`,
      description: typeof raw.description === "string" ? raw.description : "",
      tags: raw.tags,
      categories: raw.categories,
      price: { free: true, credits: 0 },
      authors: authors ?? [],
      license: {
        id: "cc0",
        name: "CC0 1.0",
        url: "https://creativecommons.org/publicdomain/zero/1.0/",
        attribution_required: false
      },
      attribution_text: `Poly Haven asset ${id} (CC0).`,
      metadata_source_url: `${API}/info/${id}`,
      retrieved_utc: fetched ? this.ctx.now().toISOString() : undefined,
      variants: [],
      source_metadata: sanitizeRecord(raw)
    });
  }

  async search(params: SearchParams): Promise<SearchPage> {
    if (params.category === "audio") {
      return { items: [], next_cursor: null };
    }
    const type = params.category === "material"
      ? "textures"
      : params.category === "model"
        ? "models"
        : params.category === "image"
          ? "hdris"
          : "";
    const url = `${API}/assets${type ? `?t=${type}` : ""}`;
    const response = await this.ctx.http.json<Record<string, RawAsset>>(url, {
      refresh: params.refresh,
      signal: params.signal
    });
    const assets = Object.entries(response)
      .map(([id, raw]) => this.normalize({ ...raw, id }, true))
      .filter((asset) => params.category === "all" || asset.type === params.category)
      .filter((asset) => matchesText(asset, params.query))
      .sort((left, right) => left.title.localeCompare(right.title));
    const page = pageSlice(assets, params.cursor, PAGE_SIZE);
    return { items: page.items.slice(0, params.limit), next_cursor: page.next_cursor };
  }

  async details(asset: Asset, options: { refresh?: boolean; signal?: AbortSignal } = {}): Promise<Asset> {
    if (!options.refresh && this.isDetailed(asset)) {
      return asset;
    }
    const [info, files] = await Promise.all([
      this.ctx.http.json<Record<string, unknown>>(`${API}/info/${asset.id}`, {
        refresh: options.refresh,
        signal: options.signal
      }),
      this.ctx.http.json<Record<string, unknown>>(`${API}/files/${asset.id}`, {
        refresh: options.refresh,
        signal: options.signal
      })
    ]);
    const raw: RawAsset = {
      ...((asset.source_metadata ?? {}) as RawAsset),
      ...info,
      id: asset.id,
      type: (info.type as number | string | undefined) ?? (asset.type === "image" ? 0 : asset.type === "model" ? 2 : 1)
    };
    const refreshed = this.normalize(raw, true);
    const built = this.buildVariants(refreshed, files);
    return mergeAsset(asset, {
      ...refreshed,
      type: built.type,
      variants: built.variants,
      files: built.files,
      download_data: built.download_data,
      description: String(info.description ?? asset.description ?? ""),
      dimensions: info.dimensions && typeof info.dimensions === "object"
        ? info.dimensions as Asset["dimensions"]
        : asset.dimensions,
      source_metadata: sanitizeRecord({ info, files })
    });
  }

  private buildVariants(asset: Asset, files: Record<string, unknown>): {
    type: AssetType;
    variants: AssetVariant[];
    files: SourceFile[];
    download_data: Record<string, unknown>;
  } {
    const variants: AssetVariant[] = [];
    const sourceFiles: SourceFile[] = [];
    const downloadData: Record<string, unknown> = {};
    const type = asset.type;

    if (type === "material") {
      const format = files.jpg && typeof files.jpg === "object"
        ? "jpg"
        : files.png && typeof files.png === "object"
          ? "png"
          : "";
      if (format) {
        const resolutions = files[format] as Record<string, unknown>;
        for (const resolution of Object.keys(resolutions).sort()) {
          const mapsRaw = resolutions[resolution];
          if (!mapsRaw || typeof mapsRaw !== "object") {
            continue;
          }
          const maps: Partial<Record<MaterialRole, MaterialSource>> = {};
          let normalFormat: "opengl" | "directx" = "opengl";
          for (const [mapName, mapValue] of Object.entries(mapsRaw as Record<string, unknown>)) {
            const role = mappedRole(mapName);
            const source = mapSource(mapValue);
            if (!role || !source) {
              continue;
            }
            maps[role] = source;
            if (role === "normal" && mapName.toLowerCase().includes("dx")) {
              normalFormat = "directx";
            }
          }
          if (!maps.albedo || !Object.keys(maps).length) {
            continue;
          }
          const id = `${format}_${resolution}`;
          const entry = variant(id, `${resolution.toUpperCase()} ${format.toUpperCase()}`, "material", {
            resolution: slug(resolution),
            format,
            filter_key: `resolution:${slug(resolution)}`,
            filter_label: resolution.toUpperCase()
          });
          variants.push(entry);
          downloadData[entry.id] = { kind: "material", maps, normal_format: normalFormat };
          for (const [role, source] of Object.entries(maps)) {
            sourceFiles.push(fileFromUrl(source.url, `${role}.${format}`, role, source.size));
          }
        }
      }
    } else {
      for (const [formatName, rawFormats] of Object.entries(files)) {
        if (!rawFormats || typeof rawFormats !== "object") {
          continue;
        }
        for (const [resolution, rawFiles] of Object.entries(rawFormats as Record<string, unknown>)) {
          if (!rawFiles || typeof rawFiles !== "object") {
            continue;
          }
          const entries: SourceFile[] = [];
          for (const value of Object.values(rawFiles as Record<string, unknown>)) {
            const source = mapSource(value);
            if (source) {
              entries.push(fileFromUrl(source.url, `${asset.id}.${formatName}`, undefined, source.size));
            }
          }
          if (!entries.length) {
            continue;
          }
          const id = `${formatName}_${resolution}`;
          const entry = variant(id, `${formatName.toUpperCase()} ${resolution.toUpperCase()}`, "files", {
            resolution: slug(resolution),
            format: formatName,
            filter_key: `format:${slug(formatName)}`,
            filter_label: formatName.toUpperCase()
          });
          variants.push(entry);
          downloadData[entry.id] = { kind: "files", files: entries };
          sourceFiles.push(...entries);
        }
      }
    }

    if (!variants.length && asset.variants.length) {
      return {
        type,
        variants: asset.variants,
        files: asset.files ?? [],
        download_data: asset.download_data ?? {}
      };
    }
    return {
      type,
      variants: variants.sort((left, right) => left.label.localeCompare(right.label)),
      files: this.uniqueFiles(sourceFiles),
      download_data: downloadData
    };
  }

  private uniqueFiles(files: SourceFile[]): SourceFile[] {
    const seen = new Set<string>();
    return files.filter((file) => {
      const key = file.url;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });
  }

  variants(asset: Asset): AssetVariant[] {
    return asset.variants;
  }

  isDetailed(asset: Asset): boolean {
    return Boolean(asset.variants.length && Object.keys(asset.download_data ?? {}).length);
  }

  canDownload(asset: Asset): boolean {
    return canDownload(asset);
  }

  async resolveDownload(asset: Asset, variantId: string, options: { signal?: AbortSignal } = {}): Promise<DownloadPlan> {
    const detailed = this.isDetailed(asset) ? asset : await this.details(asset, { signal: options.signal });
    const entry = detailed.download_data?.[variantId] as Record<string, unknown> | undefined;
    if (!entry) {
      throw new Error(`Unknown variant for ${detailed.provider_id}:${detailed.id}: ${variantId}`);
    }
    const selected = detailed.variants.find((candidate) => candidate.id === variantId);
    if (!selected) {
      throw new Error(`Unknown variant for ${detailed.provider_id}:${detailed.id}: ${variantId}`);
    }
    if (entry.kind === "material") {
      return {
        kind: "material",
        asset: detailed,
        variant: variantId,
        maps: entry.maps as Partial<Record<MaterialRole, MaterialSource>>,
        normal_format: entry.normal_format === "directx" ? "directx" : "opengl"
      } satisfies MaterialPlan;
    }
    return {
      kind: "files",
      asset: detailed,
      variant: variantId,
      files: entry.files as SourceFile[]
    } satisfies FilesPlan;
  }
}

export const polyhavenFactory = (context: ProviderContext): Provider => new PolyHavenProvider(context);
