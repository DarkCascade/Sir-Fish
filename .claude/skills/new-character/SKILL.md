---
name: new-character
description: Add a new humanoid enemy to Sir Fish on the KayKit Rig_Medium rig. Covers the Meshy concept (restyled onto the KayKit mannequin), a smart-topology mesh, then tools/character_pipeline (build, verify, register) to fit, weight, colour, arm and bake the model and wire it into combat. Use when the user wants a new enemy, monster, bandit, NPC combatant or character model.
---

# New character on KayKit `Rig_Medium`

This is the main route for new characters. The tooling is `tools/character_pipeline/`
(read its README for spec fields and report meanings). The worked example is
`tools/character_pipeline/specs/bandit_officer.json`.

**Before starting:**
- **Non-humanoids** such as the sporecap do not fit this rig. Use CLAUDE.md's in-house
  17-bone route instead.
- **Meshy is on hold** on this project outside work the user asks for. State the cost,
  about 33 credits per character, before the first call.

## 1. Spec

Copy `specs/bandit_officer.json` to `specs/<id>.json`, then settle these with the user:
- the id and display name;
- an archetype from `archetypes.json` (`brute`, `skirmisher`, `caster`, `swarm`), plus tags;
- pools: `endless_early`, `endless_mid` and/or `boss_pool`;
- a weapon prop: a `handslot` mesh node from `assets/meshes/knight.glb`, `rogue.glb` or
  `mage.glb`;
- the clips. Run `python tools/character_pipeline/pipeline.py doctor` once, then read
  names from `scratch/character_pipeline/_kaykit/Rig_Medium/clip_index.json`;
- palette anchors, taken from §6.1 in `scripts/autoload/tuning.gd`.

## 2. Concept — review point 1

1. **Costume pass.** `meshy_text_to_image`, `nano-banana-pro`, `pose_mode: "t-pose"`
   (9 credits). Follow the pattern of the bandit spec's `concept.costume_prompt`:
   - full body, front view, T-pose, **empty hands** (weapons are props, never modelled in);
   - a **hip-length top** (coat tails deform badly with the legs);
   - the palette hexes;
   - "chunky stylized low-poly, chibi proportions, faceted, no bevels, flat solid colours,
     thick dark outline, plain white background".
2. **Restyle pass.** `meshy_image_to_image`, `nano-banana-pro` (9 credits), with
   `reference_file_paths` = [`tools/character_pipeline/templates/mannequin_tpose_front.png`,
   the concept]. Follow the pattern of `concept.restyle_prompt`.
3. **Save and show.** Save both into `design documents/reference/<id>/` as `concept.png`
   and `concept_kaykit_proportions.png`, and show the user. Redo the restyle if the arms
   droop or the head and hat don't fill the mannequin's head block.

An untested shortcut: skip step 1 and restyle straight from the template, with the
costume described in text. It saves 9 credits, but it has not been tried yet.

## 3. Mesh

`meshy_image_to_3d` with these parameters (15 credits):
- `input_task_id`: the restyle task
- `model_type: "smart-topology"`, `ai_model: "meshy-t2"`
- `pose_mode: "t-pose"`
- `should_texture: true` (the palette snap needs the texture)
- `target_formats: ["glb"]`

Download it with `save_to` set to `design documents/reference/<id>/meshy_raw.glb`; the base
colour PNG lands beside it. Put both paths in the spec (`raw_mesh`, `raw_texture`).

## 4. Build and verify — review point 2

```bash
python tools/character_pipeline/pipeline.py build <id>
python tools/character_pipeline/pipeline.py verify <id>
```

Read the printed report, view `scratch/character_pipeline/<id>/pose_sheet.png`, and show
the user the sheet. Fix problems in the spec and rebuild, never in the scripts:
- fit warnings: `fit` / `weights` overrides, or a better restyle image;
- a loose palette ΔE: move or add an anchor;
- a non-overhead attack: a numeric `impact`;
- a deformation CHECK: look at that clip's row before accepting it.

## 5. Publish and register

```bash
python tools/character_pipeline/pipeline.py build <id> --publish
python tools/character_pipeline/pipeline.py register <id> --dry-run
python tools/character_pipeline/pipeline.py register <id>
```

Then have the editor import the new files: `execute_editor_script` with
`EditorInterface.get_resource_filesystem().scan()`.

## 6. Test

Run each of these with `run_headless_scene`:
- `res://tests/test_content_registry.tscn`
- `res://tests/test_animation_clips.tscn`
- `res://tests/test_endless_level_gen.tscn`
- `res://tests/test_quest_gen.tscn`
- `res://tests/test_quest_generator.tscn`
- `res://tests/test_level_curves.tscn`

## 7. In-game look (optional)

Runs autosave the real dev profile, so **copy
`%APPDATA%/Godot/app_userdata/Sir Fish/profile.save` first**. Then:
1. `play_scene` main.
2. From town, `execute_game_script` with
   `get_node("/root/Debug").command = "quest easy"`.
3. Once `get_node("/root/Debug")._director()` returns a director, spawn with
   `command = "spawn <id>"`.
4. Guard every `director.enemies` entry with `is_instance_valid()`, because it keeps
   freed combatants.
5. Stop the scene when done.

## Gotchas

- **Ad-hoc Blender scripts** go in a file written with the Write tool; long heredocs
  break the Bash tool's quoting. Never save over `blender/Sir Fish.blend`.
- **Deletes are denied** by the permission rules (`rm -rf`). Keep throwaway work under
  the gitignored `scratch/`.
- **Commit together:** the spec, `design documents/reference/<id>/`, the published glb
  with its extracted `<id>_albedo.png`, and the registered resources.
