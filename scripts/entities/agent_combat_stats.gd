extends RefCounted

var _agent: Node

var received_by_actor: Dictionary:
	get:
		return _agent.get("combat_damage_received_by_actor") as Dictionary
var received_weapon_by_actor: Dictionary:
	get:
		return _agent.get("combat_damage_received_weapon_by_actor") as Dictionary
var dealt_to_actor: Dictionary:
	get:
		return _agent.get("combat_damage_dealt_to_actor") as Dictionary
var dealt_weapon_by_actor: Dictionary:
	get:
		return _agent.get("combat_damage_dealt_weapon_by_actor") as Dictionary
var received_by_life: Dictionary:
	get:
		return _agent.get("combat_damage_received_by_life") as Dictionary
var received_weapon_by_life: Dictionary:
	get:
		return _agent.get("combat_damage_received_weapon_by_life") as Dictionary
var dealt_to_actor_by_life: Dictionary:
	get:
		return _agent.get("combat_damage_dealt_to_actor_by_life") as Dictionary

func setup(agent: Node) -> void:
	_agent = agent

func record_damage_received(actor: Node, amount: float, weapon_name: String = "") -> void:
	if not is_instance_valid(actor) or amount <= 0.0:
		return
	var actor_id := actor.get_instance_id()
	received_by_actor[actor_id] = float(received_by_actor.get(actor_id, 0.0)) + amount
	var actor_life := int(actor.get("combat_life_id")) if _has_property(actor, "combat_life_id") else 0
	_add_life_damage(received_by_life, actor_id, actor_life, amount)
	if not weapon_name.is_empty():
		received_weapon_by_actor[actor_id] = weapon_name
		var weapons_by_life: Dictionary = received_weapon_by_life.get(actor_id, {})
		weapons_by_life[actor_life] = weapon_name
		received_weapon_by_life[actor_id] = weapons_by_life

func record_damage_dealt(actor: Node, amount: float, weapon_name: String = "") -> void:
	if not is_instance_valid(actor) or amount <= 0.0:
		return
	var actor_id := actor.get_instance_id()
	dealt_to_actor[actor_id] = float(dealt_to_actor.get(actor_id, 0.0)) + amount
	if not weapon_name.is_empty():
		dealt_weapon_by_actor[actor_id] = weapon_name
	var actor_life := int(actor.get("combat_life_id")) if _has_property(actor, "combat_life_id") else 0
	_add_life_damage(dealt_to_actor_by_life, actor_id, actor_life, amount)

func _add_life_damage(history: Dictionary, actor_id: int, life_id: int, amount: float) -> void:
	var life_damage: Dictionary = history.get(actor_id, {})
	life_damage[life_id] = float(life_damage.get(life_id, 0.0)) + amount
	history[actor_id] = life_damage

func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false

func get_damage_received_from(actor: Node) -> float:
	if not is_instance_valid(actor):
		return 0.0
	return float(received_by_actor.get(actor.get_instance_id(), 0.0))

func get_damage_received_total() -> float:
	return _sum_values(received_by_actor)

func get_damage_dealt_to(actor: Node) -> float:
	if not is_instance_valid(actor):
		return 0.0
	return float(dealt_to_actor.get(actor.get_instance_id(), 0.0))

func get_damage_dealt_total() -> float:
	return _sum_values(dealt_to_actor)

func _sum_values(values: Dictionary) -> float:
	var total := 0.0
	for damage in values.values():
		total += float(damage)
	return total
