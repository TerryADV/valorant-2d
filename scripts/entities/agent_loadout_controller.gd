extends RefCounted

var _agent: Node
var held_ability_equip_tweens: Dictionary:
	get:
		return _agent.get("held_ability_equip_tweens")

var agent_data:
	get:
		return _agent.get("agent_data")
	set(value):
		_agent.set("agent_data", value)
var ability_charges: Node:
	get:
		return _agent.get("ability_charges") as Node
	set(value):
		_agent.set("ability_charges", value)
var loaded_agent_nodes: Array[Node]:
	get:
		var nodes: Array[Node] = _agent.get("loaded_agent_nodes")
		return nodes
var active_ability_name: String:
	get:
		return str(_agent.get("active_ability_name"))
	set(value):
		_agent.set("active_ability_name", value)
var weapon_controller: Node:
	get:
		return _agent.get("weapon_controller") as Node
var is_dead: bool:
	get:
		return bool(_agent.get("is_dead"))
var shop_open: bool:
	get:
		return bool(_agent.get("shop_open"))
var multiplayer: MultiplayerAPI:
	get:
		return _agent.get_multiplayer()

const MIN_EQUIP_SCALE := 0.05

func setup(agent: Node) -> void:
	_agent = agent

func configure_agent(data: Variant) -> bool:
	if not data:
		push_error("Cannot configure BaseAgent with empty AgentData.")
		return false
	if agent_data == data and (not data.loadout_scene or not loaded_agent_nodes.is_empty()):
		return false
	apply_active_ability("")
	for loadout_node in loaded_agent_nodes:
		if is_instance_valid(loadout_node):
			loadout_node.free()
	loaded_agent_nodes.clear()
	ability_charges = null
	agent_data = data
	configure_loadout()
	apply_agent_data()
	return true

func configure_loadout() -> void:
	if not agent_data or not agent_data.loadout_scene:
		return
	var loadout_scene: PackedScene = agent_data.loadout_scene
	var loadout: Node = loadout_scene.instantiate()
	if not loadout:
		push_error("Could not instantiate agent loadout for %s." % agent_data.agent_name)
		return
	var component_container := _agent.get_node_or_null("Components")
	var visual_container := _agent.get_node_or_null("Visuals")
	var loadout_components := loadout.get_node_or_null("Components")
	var loadout_visuals := loadout.get_node_or_null("Visuals")
	if not component_container or not visual_container or not loadout_components or not loadout_visuals:
		loadout.free()
		push_error("Agent loadout must contain Components and Visuals child nodes.")
		return
	for child in loadout_visuals.get_children():
		child.owner = null
		loadout_visuals.remove_child(child)
		visual_container.add_child(child)
		loaded_agent_nodes.append(child)
	for child in loadout_components.get_children():
		child.owner = null
		loadout_components.remove_child(child)
		component_container.add_child(child)
		loaded_agent_nodes.append(child)
		if (
			ability_charges == null
			and child.has_method("get_charge_state")
			and child.has_signal("charge_state_changed")
		):
			ability_charges = child
	loadout.free()

func set_active_ability(ability_name: String) -> void:
	if ability_name != "" and not has_ability_component(ability_name):
		push_error("Unknown ability selection: %s" % ability_name)
		return
	if ability_name != "" and not has_ability_charge(ability_name):
		return
	if ability_name != "" and bool(_agent.call("has_local_authority")):
		AudioManager.stop_local_cue(&"weapon_equip")
	apply_active_ability(ability_name)
	if not multiplayer.has_multiplayer_peer():
		return
	var owner_peer_id := _agent.get_multiplayer_authority()
	if multiplayer.is_server():
		NetworkManager.broadcast_player_active_ability(owner_peer_id, ability_name)
	elif _agent.is_multiplayer_authority():
		NetworkManager.request_player_active_ability_rpc.rpc_id(
			1, owner_peer_id, ability_name
		)

func has_ability_charge(ability_name: String) -> bool:
	if ability_charges and ability_charges.has_method("has_ability_charge"):
		return bool(ability_charges.call("has_ability_charge", ability_name))
	return has_ability_component(ability_name)

func consume_ability_charge(ability_name: String) -> bool:
	if ability_charges and ability_charges.has_method("consume_ability_charge"):
		return bool(ability_charges.call("consume_ability_charge", ability_name))
	return has_ability_component(ability_name)

func has_ultimate_charge() -> bool:
	if ability_charges and ability_charges.has_method("has_ultimate_charge"):
		return bool(ability_charges.call("has_ultimate_charge"))
	return true

func consume_ultimate_charge() -> bool:
	if ability_charges and ability_charges.has_method("consume_ultimate_charge"):
		return bool(ability_charges.call("consume_ultimate_charge"))
	return true

func get_ability_charge_state() -> Dictionary:
	if ability_charges and ability_charges.has_method("get_charge_state"):
		return ability_charges.call("get_charge_state")
	return {}

func has_ability_component(ability_name: String) -> bool:
	if not agent_data or ability_name not in agent_data.ability_component_ids:
		return false
	var index: int = agent_data.ability_component_ids.find(ability_name)
	return (
		index < agent_data.ability_component_paths.size()
		and _agent.get_node_or_null(agent_data.ability_component_paths[index]) != null
	)

func animate_held_ability_equip(sprite: Sprite2D, base_scale: Vector2, equipped: bool) -> void:
	if not is_instance_valid(sprite):
		return
	var sprite_id := sprite.get_instance_id()
	if held_ability_equip_tweens.has(sprite_id):
		var previous_tween: Tween = held_ability_equip_tweens[sprite_id]
		if previous_tween.is_running():
			previous_tween.kill()
	if not equipped:
		sprite.scale = base_scale
		held_ability_equip_tweens.erase(sprite_id)
		return
	var equip_duration := 0.15
	var current_weapon := weapon_controller.get("current_weapon") as WeaponData
	if current_weapon:
		equip_duration = maxf(current_weapon.equip_time, 0.01)
	sprite.scale = base_scale * MIN_EQUIP_SCALE
	var equip_tween := sprite.create_tween()
	equip_tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	equip_tween.tween_property(sprite, "scale", base_scale, equip_duration)
	held_ability_equip_tweens[sprite_id] = equip_tween

func apply_active_ability(ability_name: String) -> void:
	var was_ability_equipped := not active_ability_name.is_empty()
	active_ability_name = ability_name
	if not agent_data:
		return
	var component_container := _agent.get_node_or_null("Components")
	if component_container:
		for component in component_container.get_children():
			if component.has_method("on_agent_active_ability_changed"):
				component.call("on_agent_active_ability_changed", ability_name)
	for index in range(agent_data.ability_component_ids.size()):
		if index >= agent_data.ability_component_paths.size():
			continue
		var ability := _agent.get_node_or_null(agent_data.ability_component_paths[index])
		if not ability or not ability.has_method("_set_equipped"):
			continue
		var equipped: bool = agent_data.ability_component_ids[index] == ability_name
		if ability.get("is_equipped") != equipped:
			ability.call("_set_equipped", equipped)
	if was_ability_equipped != (not ability_name.is_empty()):
		_sync_weapon_hud_selection(ability_name.is_empty())

func _sync_weapon_hud_selection(weapon_selected: bool) -> void:
	if not bool(_agent.call("has_local_authority")):
		return
	var hud := _agent.get_parent().get_node_or_null("HUD")
	if not hud or not hud.has_method("set_weapon_slot_selected"):
		return
	hud.call(
		"set_weapon_slot_selected",
		int(weapon_controller.get("current_weapon_slot")),
		weapon_selected
	)

func reset_for_new_round() -> void:
	apply_active_ability("")
	for ability in loaded_agent_nodes:
		if is_instance_valid(ability) and ability.has_method("reset_for_new_round"):
			ability.call("reset_for_new_round")

func apply_agent_data() -> void:
	_agent.set("run_speed", agent_data.run_speed)
	_agent.set("walk_speed_ratio", agent_data.walk_speed_ratio)
	_agent.set("acceleration", agent_data.acceleration)
	_agent.set("friction", agent_data.friction)
	var health_component := _agent.get("health_component") as HealthComponent
	health_component.configure_health(agent_data.max_health, agent_data.max_shield)
	var visuals := _agent.get("visuals") as AgentVisualController
	visuals.apply_agent_data(agent_data)
