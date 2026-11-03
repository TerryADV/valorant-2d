extends RefCounted

var _controller: Node

func setup(controller: Node) -> void:
	_controller = controller

func toggle_aiming() -> void:
	var current_weapon := _controller.get("current_weapon") as WeaponData
	if not current_weapon or not current_weapon.can_aim:
		return
	var aim_level := int(_controller.get("aim_level"))
	if not bool(_controller.get("aiming")):
		_controller.set("aiming", true)
		_controller.set("aim_level", 1)
	elif current_weapon.aim_zoom_secondary > 1.0 and aim_level == 1:
		_controller.set("aim_level", 2)
	else:
		_controller.set("aiming", false)
		_controller.set("aim_level", 0)

func select_weapon_slot(
	slot: int,
	sync_network: bool = true,
	animate_equip: bool = true
) -> void:
	var weapon_slots: Array = _controller.get("weapon_slots")
	if slot < 0 or slot >= weapon_slots.size() or not weapon_slots[slot]:
		return
	var agent := _controller.get("agent") as BaseAgent
	var current_slot := int(_controller.get("current_weapon_slot"))
	var blade_storm := agent.get_node_or_null("Components/BladeStormAbility")
	var blade_storm_active: bool = blade_storm != null and bool(blade_storm.get("is_active"))
	var returning_from_ability := (
		not agent.active_ability_name.is_empty()
		or bool(_controller.get("weapon_hidden_by_ability"))
	)
	if slot == current_slot and not blade_storm_active and not returning_from_ability:
		return
	if blade_storm_active:
		blade_storm.call("end_for_weapon_switch")
	var resurrection := agent.get_node_or_null("Components/Resurrection")
	if resurrection and resurrection.has_method("handle_weapon_equipped"):
		resurrection.call("handle_weapon_equipped")
	_controller.call("stop_melee_attack_animation")
	var changed_slot := true
	if agent.has_method("set_active_ability"):
		agent.set_active_ability("")
	_controller.set("weapon_hidden_by_ability", false)

	var current_weapon := _controller.get("current_weapon") as WeaponData
	if current_weapon and not current_weapon.is_melee:
		_controller.get("slot_ammo")[current_slot] = _controller.get("ammo_in_magazine")
		_controller.get("slot_reserve_ammo")[current_slot] = _controller.get("reserve_ammo")
		_controller.get("slot_initialized")[current_slot] = true

	_controller.set("current_weapon_slot", slot)
	_controller.call("stop_reload_animation")
	current_weapon = weapon_slots[slot] as WeaponData
	_controller.set("current_weapon", current_weapon)
	_controller.set("reload_timer", 0.0)
	_controller.set("recoil_degrees", 0.0)
	_controller.set("aiming", false)
	_controller.set("aim_level", 0)

	if current_weapon.is_melee:
		_controller.set("ammo_in_magazine", 0)
		_controller.set("reserve_ammo", 0)
	else:
		var slot_initialized: Array = _controller.get("slot_initialized")
		if not slot_initialized[slot]:
			_controller.set("ammo_in_magazine", current_weapon.magazine_size)
			_controller.set("reserve_ammo", current_weapon.reserve_ammo)
			_controller.get("slot_ammo")[slot] = current_weapon.magazine_size
			_controller.get("slot_reserve_ammo")[slot] = current_weapon.reserve_ammo
			slot_initialized[slot] = true
		else:
			_controller.set("ammo_in_magazine", _controller.get("slot_ammo")[slot])
			_controller.set("reserve_ammo", _controller.get("slot_reserve_ammo")[slot])

	_controller.call("update_visual", animate_equip or returning_from_ability)
	_controller.emit_signal("weapon_changed", current_weapon, slot)
	if (changed_slot or returning_from_ability) and agent.has_local_authority():
		AudioManager.play_local_cue(current_weapon.equip_audio, &"weapon_equip")
	if sync_network and _controller.get_multiplayer().has_multiplayer_peer() and agent.has_local_authority():
		var peer_id := agent.get_multiplayer_authority()
		if _controller.get_multiplayer().is_server():
			NetworkManager.sync_player_weapon.rpc(peer_id, slot)
		else:
			NetworkManager.request_weapon_sync.rpc_id(1, peer_id, slot)

func cycle_weapon_slot(direction: int) -> void:
	var weapon_slots: Array = _controller.get("weapon_slots")
	if weapon_slots.is_empty() or direction == 0:
		return
	var agent := _controller.get("agent") as BaseAgent
	var blade_storm := agent.get_node_or_null("Components/BladeStormAbility")
	if blade_storm and bool(blade_storm.get("is_active")):
		blade_storm.call("end_for_weapon_switch")
	if (
		not agent.active_ability_name.is_empty()
		or bool(_controller.get("weapon_hidden_by_ability"))
	):
		_controller.call("select_weapon_slot", _controller.get("current_weapon_slot"))
		return
	var slot := int(_controller.get("current_weapon_slot")) + direction
	while slot >= 0 and slot < weapon_slots.size():
		if weapon_slots[slot]:
			_controller.call("select_weapon_slot", slot)
			return
		slot += direction
