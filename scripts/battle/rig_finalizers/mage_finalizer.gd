extends RefCounted
## RigProfile.finalizer for the mage (content-phase-0 spec §3 Step 3) - the
## staff's charge-glow baseline material. The KayKit mage asset ships one
## two-handed staff and a one-handed wand plus an open/closed spellbook, all
## visible="true" at export; hiding the surplus (wand, open spellbook) is pure
## data now (RigProfile.hidden_parts) - this finalizer is only the genuinely
## procedural remainder.
##
## The staff carries the charge glow: this asset has no separate orb submesh
## the way the old in-house rig did, so the whole staff mesh gets the emissive
## material instead of an isolated crystal. CombatantBakedAnimations drives
## emission_strength from 1.5 to 5.0 across the cast via a plain
## shader-parameter value track (not a bone track), so this only needs to set
## the baseline material once - guarded by checking the existing material
## rather than reading state back off a track the FIRST setup() call already
## wrote (spec 8.2b.2).

func apply(rig: Node3D, _stats: CombatantStats) -> void:
	var staff := CombatantRig.find_by_name(rig, "2H_Staff") as MeshInstance3D
	if staff == null:
		return
	var existing := staff.material_override
	if not (existing is ShaderMaterial
			and (existing as ShaderMaterial).get_shader_parameter("emission_strength") != null
			and (existing as ShaderMaterial).get_shader_parameter("emission_strength") > 0.0):
		staff.material_override = CelMaterials.cel(Tuning.C_MAGE_ACCENT, Tuning.C_MAGE_ACCENT, 1.5)
