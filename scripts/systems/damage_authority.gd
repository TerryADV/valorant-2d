class_name DamageAuthority
extends Node

signal damage_applied(target: Node, amount: float)

@export var allow_local_damage: bool = true

func request_hit(collider: Object, damage: float, shooter: Node = null, weapon_name: String = "") -> bool:
	if not allow_local_damage and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			return _apply_hit(collider, damage, shooter, weapon_name)
		request_hit_rpc.rpc_id(1, get_path_to(collider), damage, get_path_to(shooter) if shooter else NodePath(), weapon_name)
		return false

	return _apply_hit(collider, damage, shooter, weapon_name)

@rpc("any_peer", "reliable")
func request_hit_rpc(collider_path: NodePath, damage: float, shooter_path: NodePath, weapon_name: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var shooter := get_node_or_null(shooter_path) as Node
	if not shooter or shooter.get_multiplayer_authority() != sender_id:
		return

	var collider := get_node_or_null(collider_path)
	if collider:
		_apply_hit(collider, damage, shooter, weapon_name)

func _apply_hit(collider: Object, damage: float, shooter: Node = null, weapon_name: String = "") -> bool:
	var target := DamageSystem.resolve_target(collider)
	if not target or not target.has_method("take_damage"):
		return false
	if shooter and DamageSystem.is_same_actor(target, shooter):
		return false
	if shooter and DamageSystem.is_same_skirmish_team(target, shooter):
		return false

	target.take_damage(damage, shooter, weapon_name)
	damage_applied.emit(target, damage)
	return true
