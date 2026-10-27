import os from "node:os";
import path from "node:path";

export interface RuntimeConfig {
  home: string;
  output: string;
  cache: string;
  catalog_file: string;
  inventory_file: string;
  http_host: string;
  http_port: number;
  http_token?: string;
  cors_origin?: string;
  provider_ids?: string[];
  disabled_provider_ids: string[];
  provider_dirs: string[];
  offline: boolean;
  request_timeout_ms: number;
  max_download_bytes: number;
  min_request_interval_ms: number;
  texel_key?: string;
  user_agent: string;
  convert_models_to_glb: boolean;
  delete_source_models: boolean;
  delete_source_textures: boolean;
  convert_audio_to_opus: boolean;
  audio_opus_bitrate: number;
  delete_source_audio: boolean;
}

export interface RuntimeConfigInput {
  home?: string;
  output?: string;
  provider_ids?: string[];
  offline?: boolean;
  request_timeout_ms?: number;
  max_download_bytes?: number;
  min_request_interval_ms?: number;
  env?: Record<string, string | undefined>;
}

function splitList(value: string | undefined): string[] {
  return (value ?? "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function positiveInt(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function defaultHome(env: Record<string, string | undefined>): string {
  if (env.ASSET_LIBRARY_HOME) {
    return path.resolve(env.ASSET_LIBRARY_HOME);
  }
  if (env.XDG_DATA_HOME) {
    return path.join(path.resolve(env.XDG_DATA_HOME), "asset-library");
  }
  return path.join(os.homedir(), ".local", "share", "asset-library");
}

export function resolveConfig(input: RuntimeConfigInput = {}): RuntimeConfig {
  const env = input.env ?? process.env;
  const home = path.resolve(input.home ?? defaultHome(env));
  const output = path.resolve(input.output ?? env.ASSET_LIBRARY_OUTPUT ?? path.join(home, "library"));
  const texelKey = env["3DTEXEL_API_KEY"] ?? env.TEXEL_API_KEY ?? env.TEXEL;
  return {
    home,
    output,
    cache: path.join(home, "cache"),
    catalog_file: path.join(home, "catalog", "assets.json"),
    inventory_file: path.join(home, "imports", "imports.json"),
    http_host: env.ASSET_LIBRARY_HOST ?? "127.0.0.1",
    http_port: positiveInt(env.ASSET_LIBRARY_PORT, 7575),
    http_token: env.ASSET_LIBRARY_TOKEN || undefined,
    cors_origin: env.ASSET_LIBRARY_CORS || undefined,
    provider_ids: input.provider_ids ?? (splitList(env.ASSET_LIBRARY_PROVIDERS).length
      ? splitList(env.ASSET_LIBRARY_PROVIDERS)
      : undefined),
    disabled_provider_ids: splitList(env.ASSET_LIBRARY_DISABLED_PROVIDERS),
    provider_dirs: splitList(env.ASSET_LIBRARY_PROVIDER_DIRS),
    offline: input.offline ?? env.ASSET_LIBRARY_OFFLINE === "1",
    request_timeout_ms: input.request_timeout_ms ?? positiveInt(env.ASSET_LIBRARY_REQUEST_TIMEOUT_MS, 30_000),
    max_download_bytes: input.max_download_bytes ?? positiveInt(env.ASSET_LIBRARY_MAX_DOWNLOAD_BYTES, 512 * 1024 * 1024),
    min_request_interval_ms: input.min_request_interval_ms ?? positiveInt(env.ASSET_LIBRARY_MIN_INTERVAL_MS, 500),
    texel_key: texelKey?.trim() || undefined,
    user_agent: env.ASSET_LIBRARY_USER_AGENT ?? "asset-library/0.1 (+https://github.com/maxugly/3dtexel)",
    convert_models_to_glb: env.CONVERT_MODELS_TO_GLB !== "0",
    delete_source_models: env.DELETE_SOURCE_MODELS !== "0",
    delete_source_textures: env.DELETE_SOURCE_TEXTURES !== "0",
    convert_audio_to_opus: env.CONVERT_AUDIO_TO_OPUS !== "0",
    audio_opus_bitrate: positiveInt(env.AUDIO_OPUS_BITRATE, 128),
    delete_source_audio: env.DELETE_SOURCE_AUDIO !== "0"
  };
}

export function providerEnabled(config: RuntimeConfig, id: string): boolean {
  if (config.provider_ids && !config.provider_ids.includes(id)) {
    return false;
  }
  return !config.disabled_provider_ids.includes(id);
}
