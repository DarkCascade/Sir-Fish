class_name RigProfile
extends Resource
## Folds the three animation-binding registries CombatantAnimations.build()
## used to dispatch across - CombatantBakedAnimations.CLIPS,
## CombatantSkeletonAnimations.SKELETON_PATH (plus its `match stats.id`), and
## CombatantAnimations._build_shadow()'s hardcoded call - behind one resource
## referenced from CombatantStats.rig_profile (content-phase-0 spec §3 Step 3).
##
## Only `clips` participates in `inherits` - it is the one field with a real
## duplication problem (the four KayKit skeleton enemies' clip blocks are
## identical except for `attack`). Every other field (source, skeleton_path,
## speed_scale, hidden_parts, finalizer) is read straight off the profile a
## character's CombatantStats actually points at, never off a parent up an
## `inherits` chain - each of those is one short value, not a five-entry block,
## so restating it on a leaf profile costs a line, not a second source of truth.

enum Source {
	BAKED,              # retargets clips off the model's own imported AnimationPlayer
	AUTHORED_SKELETON,  # GDScript-authored bone tracks on an in-house-rig Skeleton3D
	SHAPE_KEYS,         # GDScript-authored blend-shape / Visual-level tracks, no armature
}

## Merge parent, child wins - see the header comment above for why this is
## scoped to `clips` alone. Left null for a profile with nothing to inherit.
@export var inherits: RigProfile
@export var source: Source = Source.BAKED
## Only meaningful for AUTHORED_SKELETON - the Skeleton3D CombatantSkeletonAnimations
## keys its bone tracks against, relative to Visual (was SKELETON_PATH).
@export var skeleton_path: String = ""

## StringName clip name (idle/run/attack/special/hurt/die) -> a plain
## Dictionary whose shape depends on `source`:
##   BAKED             - {"clip": String, "length": float, "loop": bool,
##                        "impact"/"cast"/"charge": float (optional),
##                        "glow_node": String (optional)} - unchanged from the
##                        old CombatantBakedAnimations.CLIPS entry shape.
##   AUTHORED_SKELETON - {"builder": String} naming one of
##                        CombatantSkeletonAnimations' shared clip builders
##                        (e.g. "humanoid_idle", "orc_attack") - the choreography
##                        itself stays GDScript, since it composes against a
##                        bone's live rest transform (spec 9.0.2) and is not
##                        expressible as plain data.
##   SHAPE_KEYS        - unused; the shadow monster's four clips are still
##                        fully hardcoded in CombatantAnimations._build_shadow().
@export var clips: Dictionary = {}

## Was the orc_warlord ternary in CombatantSkeletonAnimations.build_for().
@export var speed_scale: float = 1.0

## Prop MeshInstance3D children (by name, found anywhere under the rig) to
## hide - was the identical loop in CombatantRig._finalize_ranger() /
## _finalize_mage(). Pure data: which prop meshes a shared KayKit asset ships
## that this character does not use.
@export var hidden_parts: PackedStringArray = []

## Optional procedural material/model pass for the finishing work that is not
## expressible as data - the shadow monster's smoke material + eyes + wisps,
## the orc pair's runtime recolour + warlord shoulder pads, the mage staff's
## emissive baseline. A RefCounted script exposing `apply(rig, stats)` as an
## instance method; instantiated fresh on every CombatantRig.build() call
## (cheap, and build() is documented as safe to redo on every setup()).
@export var finalizer: Script

## `clips`, merged with every ancestor's own `clips` - child keys win. This is
## the ONLY inherited view; every other accessor reads straight off the
## profile itself (see the header comment).
func resolved_clips() -> Dictionary:
	var out: Dictionary = inherits.resolved_clips() if inherits != null else {}
	for clip_name: Variant in clips:
		out[clip_name] = clips[clip_name]
	return out
