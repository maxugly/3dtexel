import path from "node:path";
import { pathToFileURL } from "node:url";
import type { RuntimeConfig } from "./config.js";
import { providerEnabled } from "./config.js";
import { builtInProviders } from "./providers/index.js";
import type {
  HttpTransport,
  Provider,
  ProviderContext,
  ProviderFactory,
  ProviderStatus
} from "./types.js";
import { pathExists } from "./util/fs.js";

export interface RegistryOptions {
  config: RuntimeConfig;
  http: HttpTransport;
  env?: Record<string, string | undefined>;
}

export class ProviderRegistry {
  private readonly providers = new Map<string, Provider>();
  private readonly enabled = new Set<string>();
  private readonly context: ProviderContext;
  private readonly config: RuntimeConfig;
  readonly warnings: string[] = [];

  constructor(options: RegistryOptions) {
    this.config = options.config;
    const context: ProviderContext = {
      http: options.http,
      env: options.env ?? process.env,
      now: () => new Date()
    };
    this.context = context;
    for (const factory of builtInProviders) {
      this.add(factory(context), options.config);
    }
  }

  private add(provider: Provider, config: RuntimeConfig): void {
    const descriptor = provider.descriptor();
    if (!/^[a-z0-9_]+$/.test(descriptor.id)) {
      throw new Error(`Invalid provider ID: ${descriptor.id}`);
    }
    if (this.providers.has(descriptor.id)) {
      throw new Error(`Duplicate provider ID: ${descriptor.id}`);
    }
    this.providers.set(descriptor.id, provider);
    if (providerEnabled(config, descriptor.id)) {
      this.enabled.add(descriptor.id);
    }
  }

  async loadExternal(directories: string[]): Promise<void> {
    for (const directory of directories) {
      const root = path.resolve(directory);
      const candidates = ["provider.mjs", "provider.js", "index.mjs", "index.js"]
        .map((name) => path.join(root, name));
      let loaded = false;
      for (const candidate of candidates) {
        if (!(await pathExists(candidate))) {
          continue;
        }
        loaded = true;
        try {
          const module = await import(pathToFileURL(candidate).href) as {
            default?: ProviderFactory;
            createProvider?: ProviderFactory;
          };
          const factory = module.default ?? module.createProvider;
          if (typeof factory !== "function") {
            throw new Error("Provider module must export a default factory function.");
          }
          const provider = await factory(this.context);
          this.add(provider, this.config);
        } catch (error) {
          this.warnings.push(`${candidate}: ${(error as Error).message}`);
        }
      }
      if (!loaded) {
        this.warnings.push(`${root}: no provider.js or provider.mjs found`);
      }
    }
  }

  get(id: string): Provider {
    const provider = this.providers.get(id);
    if (!provider) {
      throw new Error(`Unknown provider: ${id}`);
    }
    return provider;
  }

  has(id: string): boolean {
    return this.providers.has(id);
  }

  isEnabled(id: string): boolean {
    return this.enabled.has(id);
  }

  selected(ids?: string[]): Provider[] {
    if (!ids?.length) {
      return [...this.enabled].map((id) => this.get(id));
    }
    const selected: Provider[] = [];
    for (const id of ids) {
      if (!this.providers.has(id)) {
        throw new Error(`Unknown provider: ${id}`);
      }
      if (!this.enabled.has(id)) {
        throw new Error(`Provider is disabled: ${id}`);
      }
      selected.push(this.get(id));
    }
    return selected;
  }

  all(): Provider[] {
    return [...this.providers.values()];
  }

  statuses(): ProviderStatus[] {
    return [...this.providers.values()].map((provider) => {
      const descriptor = provider.descriptor();
      return {
        ...descriptor,
        enabled: this.enabled.has(descriptor.id),
        credentials: provider.credentialStatus(),
        can_search: this.enabled.has(descriptor.id),
        can_download: this.enabled.has(descriptor.id)
      };
    });
  }
}
