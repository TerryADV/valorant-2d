class_name DamageSystem
extends Node

static func apply_hit(
	collider: Object,
	damage: float,
	shooter: Node = null,
	weapon_name: String = "",
	reveal_damage_direction: bool = true,
	shape_index: int = -1
) -> bool:
	if not collider:
		return false
	if shooter and collider is Node and is_same_actor(collider, shooter):
		return false

	var target := resolve_target(collider)
	if not target or not target.has_method("take_damage"):
		return false
	var recorded_damage := damage
	if (
		shooter is BaseAgent
		and target is BaseAgent
		and shooter.get_multiplayer().has_multiplayer_peer()
		and not shooter.is_ai_dummy
		and not (target as BaseAgent).is_ai_dummy
		and shooter.get_multiplayer_authority() == (target as BaseAgent).get_multiplayer_authority()
	):
		return false
	if target is BaseAgent:
		if target.is_match_preparing or target.is_dead or target.is_invulnerable():
			return false
		var health_component := target.health_component as HealthComponent
		if health_component:
			recorded_damage = minf(
				damage,
				health_component.current_health + health_component.current_shield
			)
	if shooter and is_same_actor(target, shooter):
		return false
	if shooter and is_same_skirmish_team(target, shooter):
		return false
	if target.has_method("is_spawn_protected") and target.is_spawn_protected():
		return false

	if shooter is BaseAgent:
		shooter.mark_combat_activity()
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", collider, shape_index, damage, shooter, weapon_name)
	elif target is BaseAgent:
		target.take_damage(damage, shooter, weapon_name, reveal_damage_direction)
	else:
		target.take_damage(damage, shooter, weapon_name)
	if shooter is BaseAgent and target is BaseAgent and recorded_damage > 0.0:
		shooter.record_combat_damage_dealt(target, recorded_damage, weapon_name)
	return true

static func get_damage(_collider: Object, damage: float) -> Dictionary:
	return {
		"amount": damage,
	}

static func resolve_target(collider: Object) -> Node:
	if collider is Node:
		var current: Node = collider
		while current:
			if current.has_method("take_damage"):
				return current
			current = current.get_parent()

		var owner_node: Node = collider.owner
		while owner_node:
			if owner_node.has_method("take_damage"):
				return owner_node
			owner_node = owner_node.get_parent()

	return null

static func is_same_actor(first: Node, second: Node) -> bool:
	return first == second or first.is_ancestor_of(second) or second.is_ancestor_of(first)

static func is_same_skirmish_team(first: Node, second: Node) -> bool:
	if not first or not second or not NetworkManager.is_skirmish_mode():
		return false
	if not first is BaseAgent:
		return false
	if not second is BaseAgent:
		return false
	var first_team := int(first.get("skirmish_team"))
	var second_team := int(second.get("skirmish_team"))
	return first_team >= 0 and first_team == second_team
