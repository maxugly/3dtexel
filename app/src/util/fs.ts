import { createHash, randomBytes } from "node:crypto";
import { createReadStream } from "node:fs";
import { access, mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";

export async function ensureDir(directory: string): Promise<void> {
  await mkdir(directory, { recursive: true });
}

export async function pathExists(target: string): Promise<boolean> {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

export async function readJson<T>(file: string): Promise<T | null> {
  try {
    const raw = await readFile(file, "utf8");
    return JSON.parse(raw) as T;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return null;
    }
    throw new Error(`Could not read JSON from ${file}: ${(error as Error).message}`);
  }
}

export async function writeJsonAtomic(file: string, value: unknown): Promise<void> {
  await ensureDir(path.dirname(file));
  const temporary = `${file}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(temporary, file);
}

export async function writeTextAtomic(file: string, value: string): Promise<void> {
  await ensureDir(path.dirname(file));
  const temporary = `${file}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`;
  await writeFile(temporary, value, "utf8");
  await rename(temporary, file);
}

export async function removeTree(target: string): Promise<void> {
  await rm(target, { recursive: true, force: true });
}

export async function sha256File(file: string): Promise<string> {
  const hash = createHash("sha256");
  await new Promise<void>((resolve, reject) => {
    const stream = createReadStream(file);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", reject);
    stream.on("end", resolve);
  });
  return hash.digest("hex");
}

export function sha256Text(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function slug(value: string): string {
  const normalized = value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 72);
  return normalized || "asset";
}

const SAFE_FILENAME = /^[A-Za-z0-9][A-Za-z0-9._ -]{0,180}$/;

export function safeFilename(value: string, fallback = "asset.bin"): string {
  const base = path.basename(value).replace(/[\u0000-\u001f\u007f]/g, "").trim();
  if (!base || base === "." || base === ".." || !SAFE_FILENAME.test(base)) {
    return fallback;
  }
  return base;
}

const RESERVED_FILENAMES = new Set([
  ".gdignore",
  "asset.credits.json",
  "files.json",
  "import_receipt.json",
  "material.credits.json",
  "provenance.json"
]);

const ALLOWED_EXTENSIONS = new Set([
  "7z", "abc", "bin", "blend", "bmp", "csv", "dae", "dds", "exr", "fbx", "flac", "gif",
  "glb", "gltf", "gz", "hdr", "ico", "jpeg", "jpg", "json", "ktx", "ktx2", "m4a", "md",
  "mkv", "mov", "mp3", "mp4", "mtl", "obj", "ogg", "ogv", "pdf", "ply", "png", "psd",
  "rar", "sbsar", "stl", "svg", "tar", "tga", "tgz", "tif", "tiff", "txt", "usd",
  "usda", "usdc", "usdz", "wav", "webm", "webp", "xml", "zip"
]);

export function extensionOf(filename: string): string {
  return path.extname(filename).slice(1).toLowerCase();
}

export function isAllowedExtension(filename: string): boolean {
  return ALLOWED_EXTENSIONS.has(extensionOf(filename));
}

export function ensureAllowedFilename(filename: string): string {
  const safe = safeFilename(filename);
  if (safe !== filename) {
    throw new Error(`Unsafe filename from provider: ${JSON.stringify(filename)}`);
  }
  if (!isAllowedExtension(safe)) {
    throw new Error(`Unsupported file extension: ${JSON.stringify(path.extname(safe))}`);
  }
  const lowered = safe.toLowerCase();
  if (RESERVED_FILENAMES.has(lowered) || lowered.endsWith(".credits.json")) {
    throw new Error(`Reserved sidecar filename from provider: ${JSON.stringify(filename)}`);
  }
  return safe;
}

export function filenameFromUrl(url: string, fallback: string): string {
  try {
    const parsed = new URL(url);
    const fromQuery = parsed.searchParams.get("file") ?? parsed.searchParams.get("filename");
    const candidate = fromQuery ? path.basename(fromQuery) : path.basename(parsed.pathname);
    return safeFilename(candidate, fallback);
  } catch {
    return fallback;
  }
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export async function directorySize(directory: string): Promise<number> {
  let total = 0;
  try {
    const entries = await import("node:fs/promises").then((module) => module.readdir(directory, { withFileTypes: true }));
    for (const entry of entries) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        total += await directorySize(target);
      } else if (entry.isFile()) {
        total += (await stat(target)).size;
      }
    }
  } catch {
    return total;
  }
  return total;
}
