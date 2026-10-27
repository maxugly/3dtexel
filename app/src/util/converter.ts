import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { ensureDir, pathExists, sha256File } from "./fs.js";

export interface ModelConvertOptions {
  centerGround?: boolean;
  blenderBin?: string;
  timeoutMs?: number;
}

export interface AudioConvertOptions {
  bitrateKbps?: number;
  ffmpegBin?: string;
  timeoutMs?: number;
}

export interface ConversionResult {
  success: boolean;
  outputPath?: string;
  bytes?: number;
  sha256?: string;
  error?: string;
}

const DEFAULT_BLENDER_PATHS = [
  process.env.BLENDER_BIN,
  "/home/m/.local/bin/blender",
  "/usr/bin/blender",
  "blender"
].filter(Boolean) as string[];

const DEFAULT_FFMPEG_PATHS = [
  process.env.FFMPEG_BIN,
  "/usr/bin/ffmpeg",
  "ffmpeg"
].filter(Boolean) as string[];

async function findExecutable(candidates: string[]): Promise<string | undefined> {
  for (const candidate of candidates) {
    if (path.isAbsolute(candidate)) {
      if (await pathExists(candidate)) {
        return candidate;
      }
    } else {
      return candidate; // Let PATH resolution handle it
    }
  }
  return undefined;
}

/**
 * Converts a 3D model (e.g. .blend, .gltf, .obj) into a centered, grounded .glb
 */
export async function convertModelToGlb(
  inputPath: string,
  outputPath: string,
  options: ModelConvertOptions = {}
): Promise<ConversionResult> {
  const blender = options.blenderBin ?? (await findExecutable(DEFAULT_BLENDER_PATHS));
  if (!blender) {
    return { success: false, error: "Blender executable not found" };
  }

  await ensureDir(path.dirname(outputPath));
  const isBlend = path.extname(inputPath).toLowerCase() === ".blend";

  const script = `
import bpy
import mathutils

is_blend = ${isBlend ? "True" : "False"}
input_path = ${JSON.stringify(inputPath)}
out_glb = ${JSON.stringify(outputPath)}

if is_blend:
    bpy.ops.wm.open_mainfile(filepath=input_path)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = input_path.split('.')[-1].lower()
    if ext in ['gltf', 'glb']:
        bpy.ops.import_scene.gltf(filepath=input_path)
    elif ext == 'obj':
        try:
            bpy.ops.wm.obj_import(filepath=input_path)
        except:
            bpy.ops.import_scene.obj(filepath=input_path)
    elif ext == 'fbx':
        bpy.ops.import_scene.fbx(filepath=input_path)

all_mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if all_mesh:
    min_x = min(min((o.matrix_world @ mathutils.Vector(c)).x for c in o.bound_box) for o in all_mesh)
    max_x = max(max((o.matrix_world @ mathutils.Vector(c)).x for c in o.bound_box) for o in all_mesh)
    min_y = min(min((o.matrix_world @ mathutils.Vector(c)).y for c in o.bound_box) for o in all_mesh)
    max_y = max(max((o.matrix_world @ mathutils.Vector(c)).y for c in o.bound_box) for o in all_mesh)
    min_z = min(min((o.matrix_world @ mathutils.Vector(c)).z for c in o.bound_box) for o in all_mesh)

    center_x = (min_x + max_x) / 2.0
    center_y = (min_y + max_y) / 2.0
    offset = mathutils.Vector((-center_x, -center_y, -min_z))

    root_objects = [o for o in bpy.context.scene.objects if o.parent is None]
    for o in root_objects:
        o.location += offset

bpy.ops.export_scene.gltf(
    filepath=out_glb,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
`;

  const scriptPath = path.join(os.tmpdir(), `blend_conv_${Date.now()}_${Math.random().toString(36).slice(2)}.py`);
  await fs.writeFile(scriptPath, script, "utf8");

  try {
    await new Promise<void>((resolve, reject) => {
      const child = spawn(blender, ["--background", "--python", scriptPath], {
        timeout: options.timeoutMs ?? 300_000
      });
      let stderr = "";
      child.stderr?.on("data", (d) => { stderr += d.toString(); });
      child.on("close", (code) => {
        // Blender sometimes returns non-zero during shutdown crash handlers even when glb was written
        resolve();
      });
      child.on("error", reject);
    });

    if (await pathExists(outputPath)) {
      const st = await fs.stat(outputPath);
      if (st.size > 0) {
        const hash = await sha256File(outputPath);
        return { success: true, outputPath, bytes: st.size, sha256: hash };
      }
    }
    return { success: false, error: "Output GLB file was not created or was 0 bytes" };
  } catch (error) {
    return { success: false, error: (error as Error).message };
  } finally {
    await fs.rm(scriptPath, { force: true });
  }
}

/**
 * Transcodes audio file to Opus format using ffmpeg
 */
export async function convertAudioToOpus(
  inputPath: string,
  outputPath: string,
  options: AudioConvertOptions = {}
): Promise<ConversionResult> {
  const ffmpeg = options.ffmpegBin ?? (await findExecutable(DEFAULT_FFMPEG_PATHS));
  if (!ffmpeg) {
    return { success: false, error: "FFmpeg executable not found" };
  }

  await ensureDir(path.dirname(outputPath));
  const bitrate = options.bitrateKbps ?? 128;

  try {
    await new Promise<void>((resolve, reject) => {
      const child = spawn(
        ffmpeg,
        ["-y", "-i", inputPath, "-c:a", "libopus", "-b:a", `${bitrate}k`, outputPath],
        { timeout: options.timeoutMs ?? 60_000 }
      );
      let stderr = "";
      child.stderr?.on("data", (d) => { stderr += d.toString(); });
      child.on("close", (code) => {
        if (code === 0) resolve();
        else reject(new Error(`FFmpeg exited with code ${code}: ${stderr.slice(-200)}`));
      });
      child.on("error", reject);
    });

    if (await pathExists(outputPath)) {
      const st = await fs.stat(outputPath);
      if (st.size > 0) {
        const hash = await sha256File(outputPath);
        return { success: true, outputPath, bytes: st.size, sha256: hash };
      }
    }
    return { success: false, error: "Output Opus file was not created or was 0 bytes" };
  } catch (error) {
    return { success: false, error: (error as Error).message };
  }
}
