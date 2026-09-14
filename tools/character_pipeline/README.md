# Character pipeline

Turns a Meshy mesh into a game-ready Sir Fish enemy on KayKit `Rig_Medium`. The mesh is
fitted, weighted, palette-coloured and armed, and gets its clips baked in. It is then
registered as stats, a rig profile, a scene and pool entries.

- **The workflow around it** (concept prompts, Meshy calls, review points) is the
  `new-character` skill.
- **The reasoning** is in CLAUDE.md, "Adding a humanoid character on KayKit `Rig_Medium`".
- **The worked example** is `specs/bandit_officer.json`.

## Requirements

- **Blender 5.2.** Found through `BLENDER_PATH`, then the newest install under
  `C:/Program Files/Blender Foundation/`.
- **The KayKit Character Animations pack**, committed at
  `third_party/kaykit/KayKit_Character_Animations_1.1.zip`. It is extracted to
  `scratch/character_pipeline/_kaykit/` on first use.
- **System Python 3.10+** runs `pipeline.py`. Blender's bundled Python runs the stages in
  `blender/`.

## Stages

Name a spec by id (`bandit_officer`) or by path.

| Command | What it does | Writes |
|---|---|---|
| `pipeline.py doctor` | Checks Blender, the pack, the templates and the specs | nothing |
| `pipeline.py template` | Renders the T-posed mannequin from the front, side and back | `templates/` |
| `pipeline.py build <spec> [--publish]` | Welds, fits, weights, palette-snaps, attaches props, bakes clips, exports | `scratch/character_pipeline/<id>/`: `<id>.glb`, `<id>_built.blend`, `build_report.json`. `--publish` copies the glb to `assets/meshes/` |
| `pipeline.py verify <spec>` | Renders the pose sheet and checks deformation | `pose_sheet.png`, `report.md`, `report.json` |
| `pipeline.py register <spec> [--dry-run] [--force]` | Writes the stats, rig profile and scene; adds pool and clip-test entries | `resources/stats/`, `resources/rig_profiles/`, `scenes/battle/enemies/`, `resources/pools/`, `tests/test_animation_clips.gd` |

`register` never overwrites a stats, rig profile or scene file that differs from what it
would generate. It prints the diff instead, and `--force` overwrites. Pool and test
edits only ever add the id.

## Spec fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | snake_case. Names every file and the stats id; the scene node is PascalCase |
| `display_name` | | Shown in game. Defaults to the title-cased id |
| `concept` | | Documentation only: the prompts used, the reference folder, the credits spent |
| `raw_mesh` | yes | The Meshy smart-topology glb, project-relative |
| `raw_texture` | | Meshy's base colour PNG. Without it, the glb's embedded texture is used |
| `texture_size` | | Default 1024 |
| `palette` | yes | `[name, hex]` pairs. Every texel snaps to the nearest one in Lab space |
| `props` | | `[{source, node, bone, name}]`: a mesh node from another glb, bone-parented at that glb's own attachment |
| `clips` | yes | State → `{clip, length, loop}`, plus optional `impact` / `cast` / `charge` (seconds, or `"auto"`) and `impact_bone`. `idle`, `attack`, `hurt` and `die` are required; `run` and `special` are optional. Clip names come from `scratch/character_pipeline/_kaykit/Rig_Medium/clip_index.json` |
| `stats` | yes | `archetype` (from `archetypes.json`) plus overrides: `tags`, `body_color`, `accent_color`, `primary`, any numeric stat |
| `pools` | | Pool ids under `resources/pools/` |
| `scene_transform` | | Defaults to the KayKit enemy transform |
| `fit`, `weights` | | Override `FIT_DEFAULTS` / `WEIGHT_DEFAULTS` in `blender/build.py` |

## Reading the report

- **Fit.** Height against the mannequin's, the boots against the `upperleg` bones, and
  how far the arms were pulled in. A warning here usually means the concept's proportions
  or arm span were off: fix the restyle image rather than the thresholds.
- **Palette ΔE** is the mean distance of the pixels mapped to each entry. Above about 12
  on a visible share, that entry is recolouring the texture, not just flattening its
  shading. Add or move an anchor if the change is unwanted.
- **Deformation** compares edge lengths with the rest pose across nine frames of every
  clip. Edges shorter than 2% of the height are skipped, since near joints they swing
  wildly with nothing visibly wrong. A clip gets CHECK when its 99.5th-percentile stretch
  exceeds 1.9, or its 0.5th-percentile length ratio drops below 0.45. Both limits were
  calibrated on the bandit officer, whose worst clips reach 1.54 (run) and 0.60 (death).
  The pose sheet is still the judgement.
- **`"auto"` impact** lands midway between the bone's highest point and its fastest drop.
  That is tuned for overhead and downward strikes, so give a number in seconds for a
  thrust, kick or cast.

## Limits

- **Humanoids with KayKit-like proportions only.** Restyle the concept onto
  `templates/mannequin_tpose_front.png` first. Non-humanoids use the in-house rig route in
  CLAUDE.md.
- **Clips are baked into each glb,** because a `RigProfile` reads clips only from its own
  character's glb. Keep to 12 clips or fewer, the ceiling in `test_animation_clips`.
- **`register` writes enemies only.** Heroes also need a `ClassDef`.
- **Texture file names.** Godot extracts embedded textures as `<glb>_<image>.png`, so the
  pipeline names its image `albedo` and a rebuild overwrites that file instead of
  orphaning the old one.
