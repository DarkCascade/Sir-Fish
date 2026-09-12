extends RefCounted
## RigProfile.finalizer shared by orc_barbarian and orc_warlord
## (content-phase-0 spec §3 Step 3) - runtime colouring for the shared orc
## asset (spec 20.5). Unlike a generic loop, this never reads the imported
## material - every value comes from `stats` or a fixed Tuning constant, so
## it is idempotent by construction: there is nothing on the node itself for
## a second setup() call to read back incorrectly (spec 8.2b.2's trap was
## specifically about reading a material the FIRST pass had already
## overwritten; this never reads the node's own material at all).

func apply(rig: Node3D, stats: CombatantStats) -> void:
	var body := stats.body_color
	var accent := stats.accent_color
	_recolor(rig, "O_Torso", body)
	_recolor(rig, "O_Head", body)
	_recolor(rig, "O_TuskL", accent)
	_recolor(rig, "O_TuskR", accent)
	_recolor(rig, "O_ArmL", accent)
	_recolor(rig, "O_ArmR", accent)
	_recolor(rig, "O_LegL", body.darkened(0.25))
	_recolor(rig, "O_LegR", body.darkened(0.25))
	_recolor(rig, "O_WeaponHaft", Tuning.C_WOOD_DARK)
	_recolor(rig, "O_WeaponHead", Tuning.C_ORC_IRON)

	# Shoulder pads have no Blender equivalent (spec A3: "no new asset") -
	# procedural, same category as the shadow monster's eyes. Guarded for
	# idempotency the same way (spec 8.2b.2): a second setup() call must not
	# add a second pair.
	if stats.id == &"orc_warlord" and CombatantRig.find_by_name(rig, "ShoulderPadL") == null:
		CombatantRig.add_box(rig, "ShoulderPadL", Vector3(0.30, 0.16, 0.30), Vector3(-0.34, 1.34, 0), Tuning.C_GOLD)
		CombatantRig.add_box(rig, "ShoulderPadR", Vector3(0.30, 0.16, 0.30), Vector3(0.34, 1.34, 0), Tuning.C_GOLD)

func _recolor(rig: Node3D, part_name: String, color: Color) -> void:
	var mi := CombatantRig.find_by_name(rig, part_name) as MeshInstance3D
	if mi != null:
		mi.material_override = CelMaterials.cel(color)
