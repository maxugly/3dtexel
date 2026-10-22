import path from "node:path";
import { publicAsset } from "./asset.js";
import type { Catalog } from "./catalog.js";
import type { RuntimeConfig } from "./config.js";
import { creditRecord, evaluateLicense, LICENSE_STATUS } from "./license.js";
import type { ProviderRegistry } from "./registry.js";
import type {
  Asset,
  DownloadManyResult,
  DownloadedFileRecord,
  FilesPlan,
  ImportJob,
  ImportRecord,
  ImportResult,
  MaterialPlan,
  MaterialRole,
  MaterialSource,
  HttpTransport,
  Provider,
  SourceFile
} from "./types.js";
import { MATERIAL_ROLES } from "./types.js";
import {
  directorySize,
  ensureAllowedFilename,
  ensureDir,
  extensionOf,
  pathExists,
  removeTree,
  sha256Text,
  slug,
  writeJsonAtomic
} from "./util/fs.js";
import { assertHttpsUrl, sanitizeUrl } from "./util/sanitize.js";

export interface DownloadServiceOptions {
  config: RuntimeConfig;
  catalog: Catalog;
  registry: ProviderRegistry;
  http: HttpTransport;
  inventory: {
    findExisting(providerId: string, assetId: string, variant: string, output?: string): Promise<ImportRecord | undefined>;
    record(record: ImportRecord): void;
    flush(force?: boolean): Promise<void>;
  };
  now?: () => Date;
}

export interface DownloadPlanResult {
  asset: Asset;
  plan: import("./types.js").DownloadPlan;
  warnings: string[];
}

const MATERIAL_EXTENSIONS = new Set(["png", "jpg", "jpeg", "webp", "tga", "exr", "hdr", "dds"]);

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function imageExtension(url: string): string {
  try {
    const extension = extensionOf(new URL(url).pathname);
    return MATERIAL_EXTENSIONS.has(extension) ? extension : "png";
  } catch {
    return "png";
  }
}

function relativeFile(role: string | undefined, filename: string, bytes: number, sha256: string, contentType?: string): DownloadedFileRecord {
  return {
    path: filename,
    role,
    bytes,
    sha256,
    content_type: contentType
  };
}

export class DownloadService {
  private readonly config: RuntimeConfig;
  private readonly catalog: Catalog;
  private readonly registry: ProviderRegistry;
  private readonly http: HttpTransport;
  private readonly inventory: DownloadServiceOptions["inventory"];
  private readonly now: () => Date;

  constructor(options: DownloadServiceOptions) {
    this.config = options.config;
    this.catalog = options.catalog;
    this.registry = options.registry;
    this.http = options.http;
    this.inventory = options.inventory;
    this.now = options.now ?? (() => new Date());
  }

  async plan(providerId: string, assetId: string, requestedVariant?: string, signal?: AbortSignal): Promise<DownloadPlanResult> {
    const { asset, provider } = await this.resolveAsset(providerId, assetId, signal);
    const variant = this.selectVariant(provider, asset, requestedVariant);
    this.authorize(asset, provider);
    const plan = await provider.resolveDownload(asset, variant, { signal, preview: true });
    this.assertIdentity(asset, plan.asset);
    this.authorize(plan.asset, provider);
    const warnings = this.warningsFor(plan.asset, variant, plan.variant);
    if (plan.kind === "material" && !Object.keys(plan.maps).length) {
      warnings.push("This provider resolves material file URLs only during download; the preview is empty.");
    }
    return {
      asset: publicAsset(plan.asset),
      plan: this.publicPlan(plan),
      warnings
    };
  }

  async download(providerId: string, assetId: string, requestedVariant?: string, signal?: AbortSignal): Promise<ImportResult> {
    const { asset, provider } = await this.resolveAsset(providerId, assetId, signal);
    const variant = this.selectVariant(provider, asset, requestedVariant);
    this.assertPolicy(asset);
    const existing = await this.inventory.findExisting(providerId, assetId, slug(variant), this.config.output);
    if (existing) {
      return {
        reused: true,
        folder: existing.folder,
        manifest: existing.manifest,
        files: existing.files,
        credits: path.join(existing.folder, "asset.credits.json"),
        provenance: path.join(existing.folder, "provenance.json"),
        warnings: ["The requested variant is already imported with complete files."],
        requested_variant: requestedVariant ?? variant,
        returned_variant: existing.variant
      };
    }
    this.assertProvider(asset, provider);

    const plan = await provider.resolveDownload(asset, variant, { signal });
    this.assertIdentity(asset, plan.asset);
    const detailed = plan.asset;
    this.authorize(detailed, provider);
    const returned = slug(plan.variant);
    if (!returned) {
      throw new Error("The provider returned an empty variant ID.");
    }

    const folder = this.folderFor(detailed, returned);
    const complete = await this.inventory.findExisting(providerId, assetId, returned, this.config.output);
    if (complete) {
      return {
        reused: true,
        folder: complete.folder,
        manifest: complete.manifest,
        files: complete.files,
        credits: path.join(complete.folder, "asset.credits.json"),
        provenance: path.join(complete.folder, "provenance.json"),
        warnings: ["The resolved variant is already imported with complete files."],
        requested_variant: requestedVariant ?? variant,
        returned_variant: returned
      };
    }
    await this.assertFolderAvailable(folder);

    const warnings = this.warningsFor(detailed, variant, plan.variant);
    if (plan.kind === "material") {
      try {
        return await this.downloadMaterial(provider, detailed, plan, folder, requestedVariant ?? variant, warnings, signal);
      } catch (error) {
        await removeTree(folder).catch(() => undefined);
        throw error;
      }
    }
    try {
      return await this.downloadFiles(provider, detailed, plan, folder, requestedVariant ?? variant, warnings, signal);
    } catch (error) {
      await removeTree(folder).catch(() => undefined);
      throw error;
    }
  }

  async downloadMany(jobs: ImportJob[], signal?: AbortSignal): Promise<DownloadManyResult> {
    const results: DownloadManyResult["results"] = [];
    for (const job of jobs) {
      try {
        const result = await this.download(job.provider_id, job.asset_id, job.variant, signal);
        results.push({ job, result });
      } catch (error) {
        results.push({ job, error: errorMessage(error) });
      }
    }
    return { results };
  }

  private async resolveAsset(providerId: string, assetId: string, signal?: AbortSignal): Promise<{ asset: Asset; provider: Provider }> {
    const provider = this.registry.get(providerId);
    if (!this.registry.isEnabled(providerId)) {
      throw new Error(`Provider is disabled: ${providerId}`);
    }
    const stored = this.catalog.get(providerId, assetId);
    if (!stored) {
      throw new Error(`Asset ${providerId}:${assetId} is not in the local catalog. Search for it or resolve its details first.`);
    }
    this.assertPolicy(stored);
    if (!provider.isDetailed(stored)) {
      const detailed = await provider.details(stored, { signal });
      this.assertIdentity(stored, detailed);
      this.catalog.upsert(detailed);
      await this.catalog.flush();
      return { asset: detailed, provider };
    }
    return { asset: stored, provider };
  }

  private selectVariant(provider: Provider, asset: Asset, requested?: string): string {
    const variants = provider.variants(asset);
    if (!variants.length) {
      throw new Error(`No downloadable variants are available for ${asset.provider_id}:${asset.id}.`);
    }
    if (!requested?.trim()) {
      return variants[0]!.id;
    }
    const needle = requested.trim();
    const match = variants.find((variant) => variant.id === needle)
      ?? variants.find((variant) => variant.id.toLowerCase() === needle.toLowerCase())
      ?? variants.find((variant) => slug(variant.id) === slug(needle))
      ?? variants.find((variant) => variant.resolution && slug(variant.resolution) === slug(needle))
      ?? variants.find((variant) => slug(variant.label) === slug(needle));
    if (!match) {
      throw new Error(`Unknown variant ${JSON.stringify(needle)}. Available: ${variants.map((variant) => variant.id).join(", ")}`);
    }
    return match.id;
  }

  private authorize(asset: Asset, provider: Provider): void {
    this.assertPolicy(asset);
    this.assertProvider(asset, provider);
  }

  private assertPolicy(asset: Asset): void {
    if (asset.price.free !== true || asset.price.credits > 0) {
      throw new Error("Only confirmed-free, zero-credit assets may be downloaded.");
    }
    const evaluation = evaluateLicense(asset);
    if (evaluation.status === LICENSE_STATUS.BLOCKED) {
      throw new Error(`Download blocked: ${evaluation.reason}`);
    }
  }

  private assertProvider(asset: Asset, provider: Provider): void {
    if (!provider.canDownload(asset)) {
      throw new Error("The provider cannot download this variant with the current configuration.");
    }
  }

  private warningsFor(asset: Asset, requested: string, returned: string): string[] {
    const warnings: string[] = [];
    const evaluation = evaluateLicense(asset);
    if (evaluation.status === LICENSE_STATUS.UNKNOWN) {
      warnings.push(`License needs review: ${evaluation.reason}`);
    }
    if (!asset.authors.length) {
      warnings.push("The provider did not supply a creator; attribution remains marked for review.");
    }
    if (evaluation.status === LICENSE_STATUS.ATTRIBUTION) {
      warnings.push("This asset requires attribution. Keep asset.credits.json with distributed files.");
    }
    if (slug(returned) !== slug(requested)) {
      warnings.push("The returned variant may differ from the requested variant.");
    }
    return warnings;
  }

  private folderFor(asset: Asset, variant: string): string {
    const identity = sha256Text(`${asset.provider_id}:${asset.id}`).slice(0, 12);
    return path.join(
      this.config.output,
      asset.provider_id,
      `${slug(asset.title)}_${identity}`,
      variant
    );
  }

  private async assertFolderAvailable(folder: string): Promise<void> {
    if (!(await pathExists(folder))) {
      return;
    }
    const size = await directorySize(folder);
    if (size === 0) {
      await removeTree(folder);
      return;
    }
    throw new Error(`Import folder already exists and will not be overwritten: ${folder}`);
  }

  private assertIdentity(expected: Asset, actual: Asset): void {
    if (expected.provider_id !== actual.provider_id || expected.id !== actual.id) {
      throw new Error("The provider returned a different asset identity; download aborted.");
    }
  }

  private async downloadMaterial(
    _provider: Provider,
    asset: Asset,
    plan: MaterialPlan,
    folder: string,
    requested: string,
    warnings: string[],
    signal?: AbortSignal
  ): Promise<ImportResult> {
    const sources: Array<{ role: MaterialRole; source: MaterialSource }> = [];
    for (const role of MATERIAL_ROLES) {
      const source = plan.maps[role];
      if (source?.url) {
        sources.push({ role, source });
      }
    }
    if (!sources.length) {
      throw new Error("The provider returned no material maps. This provider may only resolve file URLs during download.");
    }
    if (!sources.some((entry) => entry.role === "albedo")) {
      throw new Error("The material plan has no albedo map.");
    }

    await ensureDir(path.join(folder, "_source"));
    await writeJsonAtomic(path.join(folder, "_source", ".gdignore"), {});
    const clean = publicAsset(asset);
    const record = this.creditRecord(clean, requested, plan.variant);
    await writeJsonAtomic(path.join(folder, "asset.credits.json"), record);
    await writeJsonAtomic(path.join(folder, "material.credits.json"), record);

    const maps: Record<string, string> = {};
    const hashes: Record<string, string> = {};
    const downloaded: DownloadedFileRecord[] = [];
    let total = 0;
    for (const { role, source } of sources) {
      const url = assertHttpsUrl(source.url);
      const filename = `${role}.${imageExtension(url)}`;
      const relative = path.posix.join("_source", filename);
      const destination = path.join(folder, relative);
      const result = await this.http.download(url, destination, {
        max_bytes: this.config.max_download_bytes,
        signal
      });
      total += result.bytes;
      if (total > this.config.max_download_bytes) {
        throw new Error(`Material exceeds the ${this.config.max_download_bytes} byte import limit.`);
      }
      maps[role] = relative;
      hashes[role] = result.sha256;
      downloaded.push(relativeFile(role, relative, result.bytes, result.sha256, result.content_type));
      await writeJsonAtomic(path.join(folder, `${relative}.credits.json`), {
        ...record,
        file: relative,
        sha256: result.sha256,
        bytes: result.bytes
      });
    }

    await writeJsonAtomic(path.join(folder, "material.json"), {
      schema_version: 1,
      kind: "material",
      provider_id: asset.provider_id,
      asset_id: asset.id,
      variant: plan.variant,
      normal_format: plan.normal_format,
      maps,
      material_props: plan.material_props ?? {}
    });
    const provenance = this.provenance(asset, requested, plan.variant);
    await writeJsonAtomic(path.join(folder, "provenance.json"), provenance);
    const imported = this.now().toISOString();
    const receipt = {
      schema_version: 1,
      status: "complete",
      ...provenance,
      files: downloaded,
      map_files: downloaded,
      manifest: "import_receipt.json",
      credits: "asset.credits.json",
      imported_utc: imported
    };
    await writeJsonAtomic(path.join(folder, "import_receipt.json"), receipt);
    this.recordImport(asset, requested, plan.variant, folder, downloaded, imported);
    return {
      reused: false,
      folder,
      manifest: path.join(folder, "import_receipt.json"),
      files: downloaded,
      credits: path.join(folder, "asset.credits.json"),
      provenance: path.join(folder, "provenance.json"),
      warnings,
      asset: clean,
      requested_variant: requested,
      returned_variant: plan.variant
    };
  }

  private async downloadFiles(
    _provider: Provider,
    asset: Asset,
    plan: FilesPlan,
    folder: string,
    requested: string,
    warnings: string[],
    signal?: AbortSignal
  ): Promise<ImportResult> {
    const files = this.validateFiles(plan.files);
    await ensureDir(folder);
    const clean = publicAsset(asset);
    const record = this.creditRecord(clean, requested, plan.variant);
    await writeJsonAtomic(path.join(folder, "asset.credits.json"), record);

    const downloaded: DownloadedFileRecord[] = [];
    let total = 0;
    for (const entry of files) {
      const url = assertHttpsUrl(entry.url);
      const destination = path.join(folder, entry.filename);
      const result = await this.http.download(url, destination, {
        max_bytes: this.config.max_download_bytes,
        signal
      });
      total += result.bytes;
      if (total > this.config.max_download_bytes) {
        throw new Error(`Import exceeds the ${this.config.max_download_bytes} byte limit.`);
      }
      downloaded.push(relativeFile(entry.role, entry.filename, result.bytes, result.sha256, result.content_type));
      await writeJsonAtomic(path.join(folder, `${entry.filename}.credits.json`), {
        ...record,
        file: entry.filename,
        sha256: result.sha256,
        bytes: result.bytes
      });
    }

    await writeJsonAtomic(path.join(folder, "files.json"), {
      schema_version: 1,
      kind: "files",
      provider_id: asset.provider_id,
      asset_id: asset.id,
      variant: plan.variant,
      files: downloaded
    });
    const provenance = this.provenance(asset, requested, plan.variant);
    await writeJsonAtomic(path.join(folder, "provenance.json"), provenance);
    const imported = this.now().toISOString();
    const receipt = {
      schema_version: 1,
      status: "complete",
      ...provenance,
      files: downloaded,
      manifest: "import_receipt.json",
      credits: "asset.credits.json",
      imported_utc: imported
    };
    await writeJsonAtomic(path.join(folder, "import_receipt.json"), receipt);
    this.recordImport(asset, requested, plan.variant, folder, downloaded, imported);
    return {
      reused: false,
      folder,
      manifest: path.join(folder, "import_receipt.json"),
      files: downloaded,
      credits: path.join(folder, "asset.credits.json"),
      provenance: path.join(folder, "provenance.json"),
      warnings,
      asset: clean,
      requested_variant: requested,
      returned_variant: plan.variant
    };
  }

  private validateFiles(files: SourceFile[]): SourceFile[] {
    if (!files.length) {
      throw new Error("The provider returned no downloadable files.");
    }
    if (files.length > 200) {
      throw new Error("The provider returned more than 200 files; the import was refused.");
    }
    const names = new Set<string>();
    const valid: SourceFile[] = [];
    for (const entry of files) {
      assertHttpsUrl(entry.url);
      const filename = ensureAllowedFilename(entry.filename);
      const key = filename.toLowerCase();
      if (names.has(key)) {
        throw new Error(`Duplicate source filename: ${filename}`);
      }
      names.add(key);
      valid.push({ ...entry, filename });
    }
    return valid;
  }

  private creditRecord(asset: Asset, requested: string, returned: string): Record<string, unknown> {
    return {
      ...creditRecord(asset),
      requested_variant: requested,
      returned_variant: returned,
      charged_credits: 0
    };
  }

  private provenance(asset: Asset, requested: string, returned: string): Record<string, unknown> {
    return {
      provider: asset.provider_name,
      provider_id: asset.provider_id,
      asset_id: asset.id,
      title: asset.title,
      source_url: asset.url,
      license: asset.license,
      licenses: asset.licenses ?? [asset.license],
      selected_license: asset.selected_license ?? asset.license,
      requested_variant: requested,
      returned_variant: returned,
      imported_utc: this.now().toISOString(),
      charged_credits: 0
    };
  }

  private recordImport(asset: Asset, requested: string, returned: string, folder: string, files: DownloadedFileRecord[], imported: string): void {
    this.inventory.record({
      key: `${asset.provider_id}:${asset.id}`,
      provider_id: asset.provider_id,
      asset_id: asset.id,
      title: asset.title,
      variant: slug(returned),
      requested_variant: requested,
      folder,
      manifest: path.join(folder, "import_receipt.json"),
      files,
      imported_utc: imported,
      license: asset.license.name
    });
  }

  private publicPlan(plan: import("./types.js").DownloadPlan): import("./types.js").DownloadPlan {
    const copy = structuredClone(plan);
    copy.asset = publicAsset(copy.asset);
    if (copy.kind === "material") {
      const maps: Partial<Record<MaterialRole, MaterialSource>> = {};
      for (const role of MATERIAL_ROLES) {
        const source = copy.maps[role];
        const url = source ? sanitizeUrl(source.url) : undefined;
        if (url) {
          maps[role] = { ...source, url };
        }
      }
      copy.maps = maps;
    } else {
      copy.files = copy.files.flatMap((file) => {
        const url = sanitizeUrl(file.url);
        return url ? [{ ...file, url }] : [];
      });
    }
    return copy;
  }
}
