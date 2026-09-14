#!/usr/bin/env python3
"""Sir Fish character pipeline: a Meshy mesh on KayKit Rig_Medium, as a game-ready enemy.

The route and why it works are in CLAUDE.md ("Adding a humanoid character on KayKit
Rig_Medium") and the `new-character` skill. This file is the tooling. Every stage reads
one spec, `tools/character_pipeline/specs/<id>.json` (fields in README.md), and a spec
can be named by path or by id.

    python tools/character_pipeline/pipeline.py doctor
    python tools/character_pipeline/pipeline.py template
    python tools/character_pipeline/pipeline.py build    <spec> [--publish]
    python tools/character_pipeline/pipeline.py verify   <spec>
    python tools/character_pipeline/pipeline.py register <spec> [--dry-run] [--force]

Blender runs headless (`--background --factory-startup`), found through the
BLENDER_PATH environment variable, then the newest install under
`C:/Program Files/Blender Foundation/`. Work files go to
`scratch/character_pipeline/<id>/`, which is gitignored and Godot-ignored.
"""

from __future__ import annotations

import argparse
import difflib
import glob
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent
BLENDER_SCRIPTS = HERE / "blender"
TEMPLATES_DIR = HERE / "templates"
SPECS_DIR = HERE / "specs"
ARCHETYPES = HERE / "archetypes.json"
WORK_ROOT = PROJECT / "scratch" / "character_pipeline"
KAYKIT_ZIP = PROJECT / "third_party" / "kaykit" / "KayKit_Character_Animations_1.1.zip"
KAYKIT_MEMBER_PREFIX = "KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium/"
KAYKIT_CACHE = WORK_ROOT / "_kaykit" / "Rig_Medium"
# The General clip file carries the 23-bone Rig_Medium armature (handslots included)
# and a weighted mannequin, which is everything the build stage needs from KayKit.
RIG_SOURCE = "Rig_Medium_General.glb"

STATE_ORDER = ["idle", "run", "attack", "special", "hurt", "die"]
# What tests/test_content_registry.gd requires of every combatant.
REQUIRED_STATES = ["idle", "attack", "hurt", "die"]
TIMING_KEYS = ["impact", "cast", "charge"]
INT_STATS = ["max_hp", "weapon_power", "magic_power", "hp_per_level", "weapon_power_per_level",
             "magic_power_per_level"]
FLOAT_STATS = ["attack_cooldown", "model_scale"]
# Every KayKit enemy scene uses this: a quarter turn to face the party, at 0.85.
DEFAULT_SCENE_TRANSFORM = "Transform3D(0, 0, 0.85, 0, 0.85, 0, -0.85, 0, 0, 0, 0, 0)"


# --- helpers ---------------------------------------------------------------------

def find_blender() -> Path:
    env = os.environ.get("BLENDER_PATH", "")
    if env and Path(env).is_file():
        return Path(env)
    installs = glob.glob("C:/Program Files/Blender Foundation/Blender */blender.exe")

    def version(path: str) -> tuple[int, int]:
        match = re.search(r"Blender (\d+)\.(\d+)", path)
        return (int(match.group(1)), int(match.group(2))) if match else (0, 0)

    if installs:
        return Path(max(installs, key=version))
    on_path = shutil.which("blender")
    if on_path:
        return Path(on_path)
    sys.exit("Blender not found. Set BLENDER_PATH to blender.exe.")


def project_path(value: str) -> Path:
    if value.startswith("res://"):
        value = value[len("res://"):]
    path = Path(value)
    return path if path.is_absolute() else PROJECT / path


def rel(path: Path | str) -> str:
    try:
        return Path(path).resolve().relative_to(PROJECT).as_posix()
    except ValueError:
        return str(path)


def pascal(char_id: str) -> str:
    return "".join(part.capitalize() for part in char_id.split("_"))


def fmt_float(value: float) -> str:
    return f"{value:g}"


def glb_json(path: Path) -> dict:
    data = path.read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + length])


def work_dir(name: str) -> Path:
    path = WORK_ROOT / name
    path.mkdir(parents=True, exist_ok=True)
    (WORK_ROOT / ".gdignore").touch()
    return path


def ensure_kaykit() -> dict[str, str]:
    """Extracts the Rig_Medium clip files from the committed zip once; returns clip -> file."""
    index_path = KAYKIT_CACHE / "clip_index.json"
    if index_path.is_file():
        return json.loads(index_path.read_text(encoding="utf-8"))
    if not KAYKIT_ZIP.is_file():
        sys.exit(f"Missing {rel(KAYKIT_ZIP)} - the KayKit Character Animations pack.")
    work_dir("_kaykit")
    KAYKIT_CACHE.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(KAYKIT_ZIP) as archive:
        for member in archive.namelist():
            if member.startswith(KAYKIT_MEMBER_PREFIX) and member.endswith(".glb"):
                (KAYKIT_CACHE / Path(member).name).write_bytes(archive.read(member))
    index: dict[str, str] = {}
    for glb in sorted(KAYKIT_CACHE.glob("*.glb")):
        for animation in glb_json(glb).get("animations", []):
            index.setdefault(animation["name"], glb.name)
    index_path.write_text(json.dumps(index, indent=1, sort_keys=True), encoding="utf-8")
    return index


def load_archetypes() -> dict:
    data = json.loads(ARCHETYPES.read_text(encoding="utf-8"))
    return {name: preset for name, preset in data.items() if not name.startswith("_")}


def load_spec(spec_arg: str) -> dict:
    candidates = [Path(spec_arg), PROJECT / spec_arg, SPECS_DIR / f"{spec_arg}.json"]
    path = next((c for c in candidates if c.is_file()), None)
    if path is None:
        sys.exit(f"No spec found for '{spec_arg}'.")
    spec = json.loads(path.read_text(encoding="utf-8"))
    problems = []
    char_id = spec.get("id", "")
    if not re.fullmatch(r"[a-z][a-z0-9_]*", char_id):
        problems.append("id must be snake_case")
    for key in ("raw_mesh", "palette", "clips", "stats"):
        if key not in spec:
            problems.append(f"missing '{key}'")
    clips = spec.get("clips", {})
    problems += [f"clips needs '{s}'" for s in REQUIRED_STATES if s not in clips]
    problems += [f"unknown clip state '{s}'" for s in clips if s not in STATE_ORDER]
    if "raw_mesh" in spec and not project_path(spec["raw_mesh"]).is_file():
        problems.append(f"raw_mesh not found: {spec['raw_mesh']}")
    if spec.get("raw_texture") and not project_path(spec["raw_texture"]).is_file():
        problems.append(f"raw_texture not found: {spec['raw_texture']}")
    archetype = spec.get("stats", {}).get("archetype")
    if archetype not in load_archetypes():
        problems.append(f"stats.archetype '{archetype}' is not in archetypes.json")
    for prop in spec.get("props", []):
        if not project_path(prop.get("source", "")).is_file():
            problems.append(f"prop source not found: {prop.get('source')}")
    if problems:
        sys.exit(f"{rel(path)} has problems:\n  - " + "\n  - ".join(problems))
    return spec


def run_blender(script: str, job: dict, work: Path) -> None:
    stem = Path(script).stem
    job_path = work / f"{stem}_job.json"
    log_path = work / f"{stem}.log"
    job_path.write_text(json.dumps(job, indent=1), encoding="utf-8")
    blender = find_blender()
    command = [str(blender), "--background", "--factory-startup", "--python-exit-code", "1",
               "--python", str(BLENDER_SCRIPTS / script), "--", str(job_path)]
    print(f"[{stem}] Blender {blender.parent.name} - log: {rel(log_path)}", flush=True)
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        start = next((i for i, line in enumerate(lines) if "Traceback" in line), max(0, len(lines) - 30))
        print("\n".join(lines[start:start + 40]))
        sys.exit(f"[{stem}] failed with exit code {result.returncode}")


# --- stages ----------------------------------------------------------------------

def cmd_doctor(_args) -> None:
    blender = find_blender()
    env = os.environ.get("BLENDER_PATH", "")
    print(f"Blender:        {blender}")
    print(f"BLENDER_PATH:   {env or '(not set in this process - restart the shell or app that launched it)'}")
    print(f"KayKit zip:     {'ok' if KAYKIT_ZIP.is_file() else 'MISSING'} ({rel(KAYKIT_ZIP)})")
    index = ensure_kaykit() if KAYKIT_ZIP.is_file() else {}
    print(f"KayKit clips:   {len(index)} Rig_Medium clips indexed")
    templates = sorted(p.name for p in TEMPLATES_DIR.glob("*.png")) if TEMPLATES_DIR.is_dir() else []
    print(f"Templates:      {', '.join(templates) or 'none - run `template`'}")
    specs = sorted(p.stem for p in SPECS_DIR.glob("*.json")) if SPECS_DIR.is_dir() else []
    print(f"Specs:          {', '.join(specs) or 'none'}")
    print(f"Archetypes:     {', '.join(load_archetypes())}")


def cmd_template(_args) -> None:
    ensure_kaykit()
    TEMPLATES_DIR.mkdir(exist_ok=True)
    run_blender("template.py", {"rig_source": str(KAYKIT_CACHE / RIG_SOURCE),
                                "out_dir": str(TEMPLATES_DIR)}, work_dir("_template"))
    for png in sorted(TEMPLATES_DIR.glob("*.png")):
        print(f"  wrote {rel(png)}")


def cmd_build(args) -> None:
    spec = load_spec(args.spec)
    char_id = spec["id"]
    index = ensure_kaykit()
    unknown = sorted({c["clip"] for c in spec["clips"].values() if c["clip"] not in index})
    if unknown:
        sys.exit(f"Not in the KayKit Rig_Medium pack: {', '.join(unknown)} "
                 f"(see {rel(KAYKIT_CACHE / 'clip_index.json')})")
    work = work_dir(char_id)
    job = {
        "project": str(PROJECT),
        "spec": spec,
        "node_name": pascal(char_id),
        "work": str(work),
        "raw_mesh": str(project_path(spec["raw_mesh"])),
        "raw_texture": str(project_path(spec["raw_texture"])) if spec.get("raw_texture") else "",
        "rig_source": str(KAYKIT_CACHE / RIG_SOURCE),
        "clip_files": sorted({str(KAYKIT_CACHE / index[c["clip"]]) for c in spec["clips"].values()}),
        "props": [dict(prop, source=str(project_path(prop["source"]))) for prop in spec.get("props", [])],
        "out_glb": str(work / f"{char_id}.glb"),
        "out_blend": str(work / f"{char_id}_built.blend"),
    }
    run_blender("build.py", job, work)
    report = json.loads((work / "build_report.json").read_text(encoding="utf-8"))
    skinned = [n.get("name") for n in glb_json(Path(job["out_glb"])).get("nodes", []) if "mesh" in n and "skin" in n]
    if job["node_name"] not in skinned:
        sys.exit(f"[build] {job['node_name']} is not skinned in {rel(job['out_glb'])} - the bind step did not run")
    fit = report["fit"]
    print(f"  glb        {rel(job['out_glb'])} ({report['glb']['bytes'] / 1024:.0f} KB, "
          f"{report['mesh']['verts']} verts / {report['mesh']['tris']} tris)")
    print(f"  fit        height {fit['height']} (mannequin {fit['mannequin_height']}), arm tip "
          f"{fit['arm_tip']}, boots {fit['boot_x']} vs upperleg ±{fit['upperleg_x']}, "
          f"arms pulled in {round((1 - fit['arm_squash']) * 100)}%")
    print(f"  parts      {report['islands']['count']}, facing rotated: {report['facing']['rotated_180']}")
    print(f"  clips      {', '.join(report['glb']['animations'])}")
    for state, value in report.get("impacts", {}).items():
        print(f"  impact     {state}: {value} s")
    for warning in report.get("warnings", []):
        print(f"  WARNING    {warning}")
    if args.publish:
        destination = PROJECT / "assets" / "meshes" / f"{char_id}.glb"
        shutil.copy2(job["out_glb"], destination)
        print(f"  published  {rel(destination)}")


def cmd_verify(args) -> None:
    spec = load_spec(args.spec)
    char_id = spec["id"]
    work = WORK_ROOT / char_id
    built = work / f"{char_id}_built.blend"
    if not built.is_file():
        sys.exit(f"No build yet - run `build {char_id}` first.")
    run_blender("verify.py", {"project": str(PROJECT), "spec": spec, "node_name": pascal(char_id),
                              "work": str(work), "built_blend": str(built),
                              "build_report": str(work / "build_report.json")}, work)
    print((work / "report.md").read_text(encoding="utf-8"))


# --- register --------------------------------------------------------------------

def godot_color(hex_code: str) -> str:
    h = hex_code.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"Color({r:.6g}, {g:.6g}, {b:.6g}, 1)"


def rig_profile_text(spec: dict, impacts: dict) -> str:
    lines = []
    states = [s for s in STATE_ORDER if s in spec["clips"]]
    for i, state in enumerate(states):
        clip = spec["clips"][state]
        parts = [f'"clip": "{clip["clip"]}"', f'"length": {fmt_float(clip["length"])}',
                 f'"loop": {"true" if clip.get("loop") else "false"}']
        for key in TIMING_KEYS:
            if key not in clip:
                continue
            value = clip[key]
            if value == "auto":
                if state not in impacts:
                    sys.exit(f"{state}.{key} is 'auto' but the build report has no measurement - run build first.")
                value = impacts[state]
            parts.append(f'"{key}": {fmt_float(value)}')
        lines.append(f'&"{state}": {{{", ".join(parts)}}}' + ("," if i < len(states) - 1 else ""))
    return ("[gd_resource type=\"Resource\" script_class=\"RigProfile\" format=3]\n\n"
            "[ext_resource type=\"Script\" path=\"res://scripts/data/rig_profile.gd\" id=\"1_rig\"]\n\n"
            "[resource]\nscript = ExtResource(\"1_rig\")\nsource = 0\nclips = {\n"
            + "\n".join(lines) + "\n}\n")


def stats_text(spec: dict) -> str:
    char_id = spec["id"]
    overrides = {k: v for k, v in spec["stats"].items() if k != "archetype"}
    stats = dict(load_archetypes()[spec["stats"]["archetype"]], **overrides)
    script_uid = (PROJECT / "scripts/data/combatant_stats.gd.uid").read_text(encoding="utf-8").strip()
    primary = stats.get("primary", "res://resources/abilities/melee_strike_generic.tres")
    body = [
        'script = ExtResource("1_stats")',
        f'id = &"{char_id}"',
        'primary = ExtResource("2_primary")',
        f'display_name = "{spec.get("display_name", char_id.replace("_", " ").title())}"',
    ]
    body += [f"{key} = {int(stats[key])}" for key in INT_STATS]
    body += [f"{key} = {fmt_float(float(stats[key]))}" for key in FLOAT_STATS]
    body += [
        f"body_color = {godot_color(stats['body_color'])}",
        f"accent_color = {godot_color(stats['accent_color'])}",
        f'scene_path = "res://scenes/battle/enemies/{char_id}.tscn"',
        'rig_profile = ExtResource("3_rig")',
        "tags = Array[StringName]([" + ", ".join(f'&"{t}"' for t in stats.get("tags", [])) + "])",
        f"threat = {int(stats['threat'])}",
        f"drop_chance = {fmt_float(float(stats['drop_chance']))}",
    ]
    return ("[gd_resource type=\"Resource\" script_class=\"CombatantStats\" load_steps=4 format=3]\n\n"
            f"[ext_resource type=\"Script\" uid=\"{script_uid}\" path=\"res://scripts/data/combatant_stats.gd\" id=\"1_stats\"]\n"
            f"[ext_resource type=\"Resource\" path=\"{primary}\" id=\"2_primary\"]\n"
            f"[ext_resource type=\"Resource\" path=\"res://resources/rig_profiles/{char_id}_rig.tres\" id=\"3_rig\"]\n\n"
            "[resource]\n" + "\n".join(body) + "\n")


def scene_text(spec: dict) -> str:
    char_id = spec["id"]
    transform = spec.get("scene_transform", DEFAULT_SCENE_TRANSFORM)
    return ("[gd_scene load_steps=4 format=3]\n\n"
            "[ext_resource type=\"PackedScene\" path=\"res://scenes/battle/combatant.tscn\" id=\"1_base\"]\n"
            f"[ext_resource type=\"Resource\" path=\"res://resources/stats/{char_id}.tres\" id=\"2_stats\"]\n"
            f"[ext_resource type=\"PackedScene\" path=\"res://assets/meshes/{char_id}.glb\" id=\"3_model\"]\n\n"
            f"[node name=\"{pascal(char_id)}\" instance=ExtResource(\"1_base\")]\n"
            "stats = ExtResource(\"2_stats\")\n\n"
            "[node name=\"Model\" parent=\"Visual/Rig\" index=\"0\" instance=ExtResource(\"3_model\")]\n"
            f"transform = {transform}\n")


def with_pool_member(text: str, char_id: str) -> str:
    match = re.search(r"explicit_ids = Array\[StringName\]\(\[(.*?)\]\)", text)
    if match is None:
        sys.exit("pool has no explicit_ids line")
    ids = re.findall(r'&"([^"]+)"', match.group(1))
    if char_id in ids:
        return text
    inner = match.group(1) + (", " if ids else "") + f'&"{char_id}"'
    return text[:match.start(1)] + inner + text[match.end(1):]


def with_clip_test_model(text: str, char_id: str) -> str:
    match = re.search(r"const MODELS := \{\n(.*?)\n\}", text, re.S)
    if match is None:
        sys.exit("tests/test_animation_clips.gd has no MODELS block")
    if f'&"{char_id}"' in match.group(1):
        return text
    entry = f'\t&"{char_id}": "res://assets/meshes/{char_id}.glb",'
    return text[:match.end(1)] + "\n" + entry + text[match.end(1):]


def cmd_register(args) -> None:
    spec = load_spec(args.spec)
    char_id = spec["id"]
    report_path = WORK_ROOT / char_id / "build_report.json"
    impacts = json.loads(report_path.read_text(encoding="utf-8")).get("impacts", {}) if report_path.is_file() else {}
    writes: list[tuple[Path, str]] = [
        (PROJECT / "resources" / "rig_profiles" / f"{char_id}_rig.tres", rig_profile_text(spec, impacts)),
        (PROJECT / "resources" / "stats" / f"{char_id}.tres", stats_text(spec)),
        (PROJECT / "scenes" / "battle" / "enemies" / f"{char_id}.tscn", scene_text(spec)),
    ]
    edits: list[tuple[Path, str]] = []
    for pool in spec.get("pools", []):
        pool_path = PROJECT / "resources" / "pools" / f"{pool}.tres"
        if not pool_path.is_file():
            sys.exit(f"Unknown pool '{pool}'")
        edits.append((pool_path, with_pool_member(pool_path.read_text(encoding="utf-8"), char_id)))
    clip_test = PROJECT / "tests" / "test_animation_clips.gd"
    edits.append((clip_test, with_clip_test_model(clip_test.read_text(encoding="utf-8"), char_id)))

    for path, text in writes + edits:
        is_new_resource = (path, text) in writes
        current = path.read_text(encoding="utf-8") if path.is_file() else None
        if current == text:
            print(f"  unchanged  {rel(path)}")
            continue
        if current is not None and is_new_resource and not args.force:
            print(f"  DIFFERS    {rel(path)} (kept; --force overwrites)")
            print("".join(difflib.unified_diff(current.splitlines(True), text.splitlines(True),
                                               "on disk", "generated")))
            continue
        verb = "would write" if args.dry_run else ("wrote" if current is None else "updated")
        if not args.dry_run:
            path.write_text(text, encoding="utf-8", newline="\n")
        print(f"  {verb:<10} {rel(path)}")
    glb = PROJECT / "assets" / "meshes" / f"{char_id}.glb"
    if not glb.is_file():
        print(f"  NOTE       {rel(glb)} does not exist yet - run `build {char_id} --publish`.")


def main() -> None:
    # Reports use ², ± and ΔE; the Windows console defaults to cp1252 and would crash on them.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="stage", required=True)
    sub.add_parser("doctor", help="check Blender, the KayKit pack, templates and specs")
    sub.add_parser("template", help="render the T-posed mannequin template images")
    build = sub.add_parser("build", help="fit, weight, colour, prop, bake and export the glb")
    build.add_argument("spec")
    build.add_argument("--publish", action="store_true", help="copy the glb to assets/meshes/")
    verify = sub.add_parser("verify", help="render the pose sheet and write the QA report")
    verify.add_argument("spec")
    register = sub.add_parser("register", help="write the stats, rig profile and scene; add to pools and tests")
    register.add_argument("spec")
    register.add_argument("--dry-run", action="store_true")
    register.add_argument("--force", action="store_true", help="overwrite differing stats/rig/scene files")
    args = parser.parse_args()
    {"doctor": cmd_doctor, "template": cmd_template, "build": cmd_build,
     "verify": cmd_verify, "register": cmd_register}[args.stage](args)


if __name__ == "__main__":
    main()
