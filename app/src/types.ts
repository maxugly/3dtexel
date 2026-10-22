export const ASSET_CATEGORIES = ["all", "material", "model", "audio", "image"] as const;
export type AssetCategory = (typeof ASSET_CATEGORIES)[number];
export type AssetType = Exclude<AssetCategory, "all">;

export const MATERIAL_ROLES = [
  "albedo",
  "normal",
  "roughness",
  "metallic",
  "ao",
  "height",
  "opacity",
  "emission"
] as const;
export type MaterialRole = (typeof MATERIAL_ROLES)[number];

export interface Author {
  name: string;
  url?: string;
}

export interface LicenseRecord {
  id?: string;
  name: string;
  url?: string;
  attribution_required?: boolean | null;
}

export interface Price {
  free: boolean;
  credits: number;
}

export interface AssetVariant {
  id: string;
  label: string;
  confirmed: true;
  kind: "material" | "files";
  resolution?: string;
  format?: string;
  lod?: string;
  triangles?: number;
  filter_key?: string;
  filter_label?: string;
}

export interface SourceFile {
  filename: string;
  url: string;
  role?: string;
  size?: number;
  sha256?: string;
  md5?: string;
  content_type?: string;
}

export interface AssetDimensions {
  x?: number;
  y?: number;
  z?: number;
  units?: string;
}

export interface Asset {
  provider_id: string;
  provider_name: string;
  id: string;
  title: string;
  type: AssetType;
  url: string;
  thumbnail_url?: string;
  description?: string;
  tags: string[];
  categories: string[];
  price: Price;
  authors: Author[];
  author_status?: "reported" | "not_supplied";
  license: LicenseRecord;
  licenses?: LicenseRecord[];
  selected_license?: LicenseRecord;
  attribution_text?: string;
  metadata_source_url?: string;
  retrieved_utc?: string;
  variants: AssetVariant[];
  files?: SourceFile[];
  download_data?: Record<string, unknown>;
  dimensions?: AssetDimensions;
  source_metadata?: Record<string, unknown>;
}

export interface MaterialSource {
  url: string;
  filename?: string;
  size?: number;
}

export interface MaterialPlan {
  kind: "material";
  asset: Asset;
  variant: string;
  maps: Partial<Record<MaterialRole, MaterialSource>>;
  normal_format: "opengl" | "directx";
  material_props?: Record<string, unknown>;
}

export interface FilesPlan {
  kind: "files";
  asset: Asset;
  variant: string;
  files: SourceFile[];
}

export type DownloadPlan = MaterialPlan | FilesPlan;

export interface ProviderDescriptor {
  id: string;
  name: string;
  website: string;
  key_env: string[];
  capabilities: AssetType[];
  description?: string;
}

export interface ProviderStatus extends ProviderDescriptor {
  enabled: boolean;
  credentials: string;
  can_search: boolean;
  can_download: boolean;
}

export interface SearchParams {
  query: string;
  category: AssetCategory;
  cursor?: string | null;
  limit: number;
  refresh?: boolean;
  signal?: AbortSignal;
}

export interface SearchPage {
  items: Asset[];
  next_cursor: string | null;
}

export interface ProviderContext {
  http: HttpTransport;
  env: Record<string, string | undefined>;
  now: () => Date;
}

export interface JsonRequestOptions {
  method?: "GET" | "POST";
  headers?: Record<string, string>;
  body?: unknown;
  refresh?: boolean;
  timeout_ms?: number;
  signal?: AbortSignal;
  pace_ms?: number;
}

export interface TextRequestOptions {
  headers?: Record<string, string>;
  refresh?: boolean;
  timeout_ms?: number;
  signal?: AbortSignal;
  pace_ms?: number;
}

export interface DownloadOptions {
  headers?: Record<string, string>;
  max_bytes?: number;
  timeout_ms?: number;
  signal?: AbortSignal;
  pace_ms?: number;
}

export interface DownloadResult {
  bytes: number;
  sha256: string;
  content_type?: string;
  final_url: string;
}

export interface HttpTransport {
  json<T>(url: string, options?: JsonRequestOptions): Promise<T>;
  text(url: string, options?: TextRequestOptions): Promise<string>;
  download(url: string, destination: string, options?: DownloadOptions): Promise<DownloadResult>;
}

export interface Provider {
  descriptor(): ProviderDescriptor;
  credentialStatus(): string;
  search(params: SearchParams): Promise<SearchPage>;
  details(asset: Asset, options?: { refresh?: boolean; signal?: AbortSignal }): Promise<Asset>;
  variants(asset: Asset): AssetVariant[];
  isDetailed(asset: Asset): boolean;
  canDownload(asset: Asset): boolean;
  resolveDownload(
    asset: Asset,
    variant: string,
    options?: { signal?: AbortSignal; preview?: boolean }
  ): Promise<DownloadPlan>;
  checkConnection?(options?: { signal?: AbortSignal }): Promise<{ ok: boolean; message: string }>;
}

export interface QualifiedId {
  provider_id: string;
  asset_id: string;
}

export interface SearchError {
  provider_id: string;
  message: string;
}

export interface SearchResponse {
  assets: Asset[];
  errors: SearchError[];
  providers: string[];
}

export interface ProviderFactoryContext extends ProviderContext {
  descriptor: ProviderDescriptor;
}

export type ProviderFactory = (context: ProviderContext) => Provider;

export interface DownloadedFileRecord {
  path: string;
  role?: string;
  bytes: number;
  sha256: string;
  content_type?: string;
}

export interface ImportRecord {
  key: string;
  provider_id: string;
  asset_id: string;
  title: string;
  variant: string;
  requested_variant: string;
  folder: string;
  manifest: string;
  files: DownloadedFileRecord[];
  imported_utc: string;
  license: string;
}

export interface ImportResult {
  reused: boolean;
  folder: string;
  manifest: string;
  files: DownloadedFileRecord[];
  credits: string;
  provenance: string;
  warnings: string[];
  asset?: Asset;
  requested_variant?: string;
  returned_variant?: string;
}

export interface ImportJob {
  provider_id: string;
  asset_id: string;
  variant: string;
}

export interface DownloadManyResult {
  results: Array<{ job: ImportJob; result?: ImportResult; error?: string }>;
}
