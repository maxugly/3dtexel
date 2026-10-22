import path from "node:path";
import type { ImportRecord } from "./types.js";
import { pathExists, readJson, writeJsonAtomic } from "./util/fs.js";

interface InventoryFile {
  schema_version: 1;
  updated_utc?: string;
  imports: ImportRecord[];
}

export interface InventoryEntry extends ImportRecord {
  exists: boolean;
  missing: string[];
}

export class Inventory {
  readonly file: string;
  private records: ImportRecord[] = [];
  private loaded = false;
  private dirty = false;

  constructor(file: string) {
    this.file = path.resolve(file);
  }

  async load(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const data = await readJson<InventoryFile>(this.file);
    if (data) {
      if (data.schema_version !== 1 || !Array.isArray(data.imports)) {
        throw new Error(`Unsupported import inventory format in ${this.file}`);
      }
      this.records = data.imports.filter((record) => record && record.key && record.folder);
    }
    this.loaded = true;
  }

  find(providerId: string, assetId: string, variant: string, output?: string): ImportRecord | undefined {
    const key = `${providerId}:${assetId}`;
    return this.records.find((record) =>
      record.key === key
      && record.variant === variant
      && (!output || record.folder === path.resolve(output) || record.folder.startsWith(`${path.resolve(output)}${path.sep}`))
    );
  }

  findAny(providerId: string, assetId: string, output?: string): ImportRecord | undefined {
    const key = `${providerId}:${assetId}`;
    return this.records.find((record) =>
      record.key === key
      && (!output || record.folder === path.resolve(output) || record.folder.startsWith(`${path.resolve(output)}${path.sep}`))
    );
  }

  async findExisting(providerId: string, assetId: string, variant: string, output?: string): Promise<ImportRecord | undefined> {
    const record = this.find(providerId, assetId, variant, output);
    if (!record) {
      return undefined;
    }
    for (const file of record.files) {
      if (!(await pathExists(path.join(record.folder, file.path)))) {
        return undefined;
      }
    }
    return record;
  }

  async validate(record: ImportRecord): Promise<InventoryEntry> {
    const missing: string[] = [];
    for (const file of record.files) {
      const target = path.resolve(record.folder, file.path);
      if (!target.startsWith(`${path.resolve(record.folder)}${path.sep}`) && target !== path.resolve(record.folder)) {
        missing.push(file.path);
        continue;
      }
      if (!(await pathExists(target))) {
        missing.push(file.path);
      }
    }
    return { ...record, exists: missing.length === 0, missing };
  }

  async list(filter: { provider_id?: string; asset_id?: string } = {}): Promise<InventoryEntry[]> {
    const selected = this.records.filter((record) =>
      (!filter.provider_id || record.provider_id === filter.provider_id)
      && (!filter.asset_id || record.asset_id === filter.asset_id)
    );
    return Promise.all(selected.map((record) => this.validate(record)));
  }

  get(key: string, variant: string): ImportRecord | undefined {
    return this.records.find((record) => record.key === key && record.variant === variant);
  }

  record(importRecord: ImportRecord): void {
    const index = this.records.findIndex((record) =>
      record.key === importRecord.key
      && record.variant === importRecord.variant
      && record.folder === importRecord.folder
    );
    if (index >= 0) {
      this.records[index] = importRecord;
    } else {
      this.records.push(importRecord);
    }
    this.records.sort((left, right) => right.imported_utc.localeCompare(left.imported_utc));
    this.dirty = true;
  }

  async flush(force = false): Promise<void> {
    if (!this.dirty && !force) {
      return;
    }
    await writeJsonAtomic(this.file, {
      schema_version: 1,
      updated_utc: new Date().toISOString(),
      imports: this.records
    } satisfies InventoryFile);
    this.dirty = false;
  }
}
