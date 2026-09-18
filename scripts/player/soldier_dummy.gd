class_name SoldierDummy
extends RefCounted

static func receive_hit(model: Node3D, damage: float, point: Vector3, direction: Vector3,
		bone: String, zone: String, strength: float) -> bool:
	var ragdoll := model.get_meta("ragdoll") as SoldierRagdoll
	var blood := model.get_meta("blood") as SoldierBlood
	var health := maxf(0.0, float(model.get_meta("health", 100.0)) - damage)
	model.set_meta("health", health)
	blood.add_wound(point, direction, bone, zone)
	if health > 0.0:
		return false
	if not ragdoll.running:
		var anim_trees := model.find_children("*", "AnimationTree", true, false)
		# start() must read bone poses BEFORE AnimationPlayer resets them to rest.
		if not anim_trees.is_empty():
			ragdoll._anim_tree = anim_trees[0] as AnimationTree
		ragdoll.start(Vector3.ZERO)
		for tree: AnimationTree in anim_trees:
			tree.active = false
		for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
			player.stop(true)
		for modifier: SoldierRigModifier in model.find_children("*", "SkeletonModifier3D", true, false).filter(func(node: Node) -> bool: return node is SoldierRigModifier):
			modifier.active = false
		for area: Area3D in model.find_children("*", "Area3D", true, false):
			area.set_deferred("collision_layer", 0)
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = SoldierRagdoll.CORPSE_LIFETIME
		model.add_child(timer)
		timer.timeout.connect(model.queue_free)
		timer.start()
	ragdoll.apply_impulse(bone, point, direction.normalized() * 4.0 * strength)
	return true
