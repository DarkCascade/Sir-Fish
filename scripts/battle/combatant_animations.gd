class_name CombatantAnimations
extends RefCounted
## Dispatches on CombatantStats.rig_profile.source (content-phase-0 spec §3
## Step 3) - BAKED to CombatantBakedAnimations, AUTHORED_SKELETON to
## CombatantSkeletonAnimations.

static func build(player: AnimationPlayer, stats: CombatantStats) -> void:
	var profile := stats.rig_profile
	assert(profile != null, "CombatantAnimations: %s has no rig_profile" % stats.id)
	match profile.source:
		RigProfile.Source.BAKED:
			CombatantBakedAnimations.build(player, profile)
		RigProfile.Source.AUTHORED_SKELETON:
			CombatantSkeletonAnimations.build(player, profile)
	player.speed_scale = profile.speed_scale
