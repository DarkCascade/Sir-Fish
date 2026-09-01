class_name ShaderWarmup
extends Node
## [perf] Forces every spatial shader variant the expedition needs to compile
## HERE, at boot, instead of on the frame the quest button is pressed.
##
## Why this exists. A Firefox profile of the town -> expedition transition
## (`design documents/Sir Fish - Shader Link Counting Experiment.md`) measured
## 12.8 s of freeze inside exactly TWO requestAnimationFrame callbacks, of which
## 97% was WebGL program linking: 61 programs, ten of them ~1 s each. Godot's
## Compatibility backend queries GL_LINK_STATUS immediately after glLinkProgram,
## so every link is a blocking round-trip to the GPU process.
##
## ## Why this instances the real battle world rather than a rig of test cubes
##
## The first version of this file built its own little viewport - one light, no
## environment - and drew a box per material family. **It did not work**, and the
## way it failed is worth recording so nobody rebuilds it that way. Measured on
## the web export, boot went from 52 programs to 60 (it compiled its own eight)
## while the transition went from 61 to 56: it had added work without removing
## any. Program COUNT is cache-independent, which is what made the failure
## visible even on a warm GPU cache where every timing looked wonderful.
##
## The cause is that Godot's GLES3 scene shader bakes **specialization constants
## off the scene's actual light and fog setup** - fog on/off, how many
## directional lights, whether omni/spot exist. A cube under one light with no
## WorldEnvironment specializes differently from the same material under
## `battle_world.tscn`'s two lights, depth fog and sky ambient, so it compiles a
## program the expedition never asks for while leaving the real one uncompiled.
##
## Hand-matching those bits is fragile - they would silently drift the next time
## a light or the fog is touched. So this instances `battle_world.tscn` itself.
## The environment, the lights and the field's own materials are then correct by
## construction, and the only things added on top are the combatant material
## families, which the empty world has no instances of.
##
## ## Two other things that are load-bearing
##
## **Everything here is actually drawn.** A variant compiles when something using
## it is RASTERIZED, not when the material is constructed - hence a real
## rendering SubViewport rather than a pile of orphan materials. Same reason
## `BattleVfx.warm_up()` puts its rig in front of a camera.
##
## **Every step yields two frames.** Without that the whole pass lands in one
## callback, the main thread never returns to the browser, and no progress bar
## can draw - which is the exact defect this is meant to cure. A ~1 s blocking
## link cannot be hidden inside a 16 ms frame, so the honest move is to yield
## between links and let a bar advance. The yield is the feature.
##
## This does not shrink the cold total; it moves it to startup, where a bar is
## expected. On a warm GPU program cache the whole pass costs milliseconds.

## The real thing, for the reasons in the header. Instancing this also runs
## `battle_world.gd._ready()` (fog from Tuning, glow off on web) and
## `overworld_field.gd`'s scatter, so the field's own materials warm too.
const BATTLE_WORLD := preload("res://scenes/battle/battle_world.tscn")

## The three mesh families the fight actually renders, each warmed with the
## material it really wears. The first cut of this file used the orc for
## everything on the theory that "skinned is skinned"; measurement said
## otherwise - boot compiled 16 expensive programs where only ~10 were needed,
## about 6 seconds of pure waste, because a variant keys on the mesh's vertex
## ATTRIBUTE LAYOUT as well as its material, and these three families do not
## share one.
##
## What CombatantRig.build() actually does, which is what this has to mirror:
##
##   KayKit (knight/rogue/mage + all four skeletons)
##       keeps the StandardMaterial3D its .glb ships - CombatantRig only hides
##       surplus props and swaps the mage's staff to an emissive cel material.
##       This is the family the whole party and most enemies are drawn with,
##       and the one the orc proxy was never standing in for.
##   In-house rig (orc barbarian / warlord)
##       every part reassigned CelMaterials.cel() at runtime, because the pair
##       share one .glb and are coloured apart from CombatantStats.
##   Shadow monster
##       CelMaterials.smoke() on the body - and note it has NO ARMATURE
##       (see CombatantRig._finalize_shadow), so smoke belongs on a STATIC
##       mesh. Warming it skinned, as the first cut did, compiled a program
##       the game never asks for.
const KAYKIT_SOURCE := preload("res://assets/meshes/knight.glb")
const INHOUSE_SOURCE := preload("res://assets/meshes/orc_barbarian.glb")
const SHADOW_SOURCE := preload("res://assets/meshes/shadow_monster.glb")

## Emitted after each step so the boot screen can advance a bar.
signal progress(done: int, total: int)

enum Step { WORLD, KAYKIT_STOCK, KAYKIT_CEL, INHOUSE_CEL, SHADOW_SMOKE, STATIC_CEL }

const STEPS: Array[Step] = [
	Step.WORLD,
	Step.KAYKIT_STOCK,
	Step.KAYKIT_CEL,
	Step.INHOUSE_CEL,
	Step.SHADOW_SMOKE,
	Step.STATIC_CEL,
]

var _viewport: SubViewport = null
var _world: Node3D = null


## Runs the whole pass. Await it.
func run() -> void:
	_build_viewport()
	var done := 0
	for step: Step in STEPS:
		_run_step(step)
		# Two frames, not one: `process_frame` resumes at the START of the next
		# frame, before it has drawn, so a single await can return before the
		# thing just added has ever been rasterized - and an unrasterized
		# material is an uncompiled one, which would silently defeat the pass.
		await get_tree().process_frame
		await get_tree().process_frame
		done += 1
		progress.emit(done, STEPS.size())
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_world = null


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	# Its own World3D so the instanced battle world cannot interact with
	# anything the boot scene has up, and is not visible anywhere.
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(64, 64)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)


func _run_step(step: Step) -> void:
	match step:
		Step.WORLD:
			_world = BATTLE_WORLD.instantiate() as Node3D
			# Out of the "battle_world" group before it enters the tree: BattleVfx
			# and MainLayout both find the live world with
			# get_first_node_in_group("battle_world"), and a decoy sitting in that
			# group - even for the few frames this lives - is exactly the kind of
			# thing that would later resolve to the wrong node.
			_world.remove_from_group(&"battle_world")
			_viewport.add_child(_world)
		Step.KAYKIT_STOCK:
			# `null` material: keep exactly the StandardMaterial3D the .glb
			# ships. This is the party and most of the bestiary, and it is the
			# single most valuable step here - overriding it would warm a
			# variant nothing renders.
			_add_glb(KAYKIT_SOURCE, null, true)
		Step.KAYKIT_CEL:
			# The mage's staff (CombatantRig._finalize_mage) - a cel material
			# with emission, on the KayKit vertex layout.
			_add_glb(KAYKIT_SOURCE, CelMaterials.cel(
				Tuning.C_MAGE_ACCENT, Tuning.C_MAGE_ACCENT, 1.5), true)
		Step.INHOUSE_CEL:
			_add_glb(INHOUSE_SOURCE, CelMaterials.cel(Color.WHITE), true)
		Step.SHADOW_SMOKE:
			# cast_shadow OFF to match _finalize_shadow: a caster would pull in
			# a shadow-pass variant the real monster never needs.
			_add_glb(SHADOW_SOURCE, CelMaterials.smoke(Color.WHITE), false)
		Step.STATIC_CEL:
			# Procedural bits with no .glb behind them: the shadow monster's
			# eyes, the warlord's shoulder pads, chest and shop props.
			_add_static(CelMaterials.cel(Color.WHITE))


## Where the warm-up geometry stands: the party's own anchor, so it is inside
## the battle camera's frustum and actually gets rasterized. Nothing is scaled
## down to hide it - this viewport is never displayed anywhere, so there is
## nothing to hide it from, and a full-size mesh is a surer rasterization than a
## sub-pixel one.
func _anchor() -> Vector3:
	return Tuning.PARTY_ANCHOR


func _add_static(mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = mat
	mi.position = _anchor()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_parent_for_rigs().add_child(mi)


## Instances `source` and draws it. A null `mat` leaves the .glb's own
## materials in place, which is the correct thing for the KayKit family -
## see the note on KAYKIT_SOURCE.
func _add_glb(source: PackedScene, mat: Material, casts_shadow: bool) -> void:
	var rig := source.instantiate() as Node3D
	rig.position = _anchor()
	_parent_for_rigs().add_child(rig)
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in _mesh_instances(rig):
		if mat != null:
			mi.material_override = mat
		mi.cast_shadow = shadow


## Rigs go under the world so they inherit its environment and lights - which is
## the entire point of instancing it. Falls back to the viewport if the world
## step somehow failed, so a broken warm-up degrades to the old behaviour rather
## than throwing during boot.
func _parent_for_rigs() -> Node:
	if is_instance_valid(_world):
		var enemies := _world.get_node_or_null(^"EnemyRoot")
		return enemies if enemies != null else _world
	return _viewport


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for child: Node in root.get_children():
		out.append_array(_mesh_instances(child))
	return out
