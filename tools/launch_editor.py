#!/usr/bin/env python3
"""Launch Godot with an inherited Texel key; never reads or writes secret files."""
import os
import shutil
import sys
from pathlib import Path

env = os.environ.copy()
key = next((env.get(name, "").strip() for name in ("TEXEL_API_KEY", "3DTEXEL_API_KEY", "TEXEL") if env.get(name, "").strip()), "")
if key:
    # A conventional variable name also survives shells that drop digit-leading names.
    env["TEXEL_API_KEY"] = key
binary = shutil.which(env.get("GODOT_BIN", "godot"))
if not binary:
    raise SystemExit("Godot not found. Set GODOT_BIN or add godot to PATH.")
project = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
if not (project / "project.godot").is_file():
    raise SystemExit("Choose a Godot project directory containing project.godot.")
os.execve(binary, [binary, "--editor", "--path", str(project)], env)
