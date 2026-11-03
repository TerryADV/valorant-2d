extends RefCounted

var _controller: Node

func setup(controller: Node) -> void:
	_controller = controller

func drop_current_weapon() -> void:
	var current_weapon := _controller.get("current_weapon") as WeaponData
	var current_slot := int(_controller.get("current_weapon_slot"))
	if not current_weapon or current_slot == 2 or current_weapon.is_melee:
		return

	var agent := _controller.get("agent") as BaseAgent
	var muzzle := _controller.get("muzzle") as Marker2D
	var ammo := int(_controller.get("ammo_in_magazine"))
	var reserve := int(_controller.get("reserve_ammo"))
	var drop_position: Vector2 = muzzle.global_position if muzzle else agent.global_position
	var direction := (agent.get_global_mouse_position() - agent.global_position).normalized()
	spawn_dropped_weapon(current_weapon, drop_position, direction, ammo, reserve)

	var weapon_slots: Array = _controller.get("weapon_slots")
	var slot_ammo: Array = _controller.get("slot_ammo")
	var slot_reserve_ammo: Array = _controller.get("slot_reserve_ammo")
	var slot_initialized: Array = _controller.get("slot_initialized")
	weapon_slots[current_slot] = null
	slot_ammo[current_slot] = 0
	slot_reserve_ammo[current_slot] = 0
	slot_initialized[current_slot] = false
	_controller.set("current_weapon", null)
	_controller.set("ammo_in_magazine", 0)
	_controller.set("reserve_ammo", 0)

	var fallback_slot := get_fallback_weapon_slot(current_slot)
	if fallback_slot >= 0:
		_controller.call("select_weapon_slot", fallback_slot)
	else:
		_controller.call("update_visual")
		_controller.emit_signal("weapon_changed", null, current_slot)

func get_fallback_weapon_slot(excluded_slot: int) -> int:
	var weapon_slots: Array = _controller.get("weapon_slots")
	if excluded_slot == 0:
		if weapon_slots.size() > 1 and weapon_slots[1]:
			return 1
		return ensure_knife_slot()
	if excluded_slot == 1:
		return ensure_knife_slot()
	if weapon_slots.size() > 0 and weapon_slots[0]:
		return 0
	if weapon_slots.size() > 1 and weapon_slots[1]:
		return 1
	return ensure_knife_slot()

func ensure_knife_slot() -> int:
	var weapon_slots: Array = _controller.get("weapon_slots")
	var slot_ammo: Array = _controller.get("slot_ammo")
	var slot_reserve_ammo: Array = _controller.get("slot_reserve_ammo")
	var slot_initialized: Array = _controller.get("slot_initialized")
	if weapon_slots.size() < 3:
		weapon_slots.resize(3)
	if not weapon_slots[2]:
		weapon_slots[2] = preload("res://resources/weapons/knife.tres")
		slot_ammo[2] = 0
		slot_reserve_ammo[2] = 0
		slot_initialized[2] = true
	return 2

func apply_shop_weapon(weapon: WeaponData) -> void:
	if not weapon or weapon.is_melee:
		return
	var target_slot := get_weapon_slot(weapon)
	var weapon_slots: Array = _controller.get("weapon_slots")
	if target_slot >= weapon_slots.size():
		return

	var slot_ammo: Array = _controller.get("slot_ammo")
	var slot_reserve_ammo: Array = _controller.get("slot_reserve_ammo")
	var slot_initialized: Array = _controller.get("slot_initialized")
	weapon_slots[target_slot] = weapon
	slot_ammo[target_slot] = weapon.magazine_size
	slot_reserve_ammo[target_slot] = weapon.reserve_ammo
	slot_initialized[target_slot] = true
	if target_slot == int(_controller.get("current_weapon_slot")):
		_controller.call("stop_melee_attack_animation")
		_controller.set("ammo_in_magazine", weapon.magazine_size)
		_controller.set("reserve_ammo", weapon.reserve_ammo)
		_controller.set("current_weapon", weapon)
		_controller.set("reload_timer", 0.0)
		_controller.set("recoil_degrees", 0.0)
		_controller.call("update_visual", true)
		var agent := _controller.get("agent") as BaseAgent
		if agent.has_local_authority():
			AudioManager.play_local_cue(weapon.equip_audio, &"weapon_equip")
	else:
		_controller.call("select_weapon_slot", target_slot, false)
	_controller.emit_signal("weapon_changed", _controller.get("current_weapon"), _controller.get("current_weapon_slot"))

func try_pickup_weapon() -> void:
	var agent := _controller.get("agent") as BaseAgent
	var circle := CircleShape2D.new()
	circle.radius = 28.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, agent.global_position)
	query.collision_mask = 16
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in agent.get_world_2d().direct_space_state.intersect_shape(query):
		var dropped := result.collider as DroppedWeapon
		if dropped and dropped.can_be_picked and not dropped.weapon_data.is_melee:
			equip_dropped_weapon(dropped)
			return

func try_auto_pickup_weapon(dropped: DroppedWeapon) -> void:
	if not dropped or not dropped.can_be_picked or dropped.weapon_data.is_melee:
		return
	var target_slot := get_weapon_slot(dropped.weapon_data)
	var weapon_slots: Array = _controller.get("weapon_slots")
	if target_slot < weapon_slots.size() and not weapon_slots[target_slot]:
		equip_dropped_weapon(dropped)

func equip_dropped_weapon(dropped: DroppedWeapon) -> void:
	if not dropped or not dropped.can_be_picked or dropped.weapon_data.is_melee:
		return
	var target_slot := get_weapon_slot(dropped.weapon_data)
	var weapon_slots: Array = _controller.get("weapon_slots")
	if target_slot >= weapon_slots.size():
		return

	var current_slot := int(_controller.get("current_weapon_slot"))
	var was_active_slot := target_slot == current_slot
	var weapon_in_slot := weapon_slots[target_slot] as WeaponData
	if weapon_in_slot and not weapon_in_slot.is_melee:
		drop_slot_weapon(target_slot)

	var slot_ammo: Array = _controller.get("slot_ammo")
	var slot_reserve_ammo: Array = _controller.get("slot_reserve_ammo")
	var slot_initialized: Array = _controller.get("slot_initialized")
	weapon_slots[target_slot] = dropped.weapon_data
	slot_ammo[target_slot] = dropped.ammo_in_magazine
	slot_reserve_ammo[target_slot] = dropped.reserve_ammo
	slot_initialized[target_slot] = true
	dropped.queue_free()

	if was_active_slot:
		_controller.set("current_weapon", null)
		_controller.call("select_weapon_slot", target_slot)
	else:
		_controller.emit_signal("weapon_changed", _controller.get("current_weapon"), current_slot)

func get_weapon_slot(weapon: WeaponData) -> int:
	if not weapon or weapon.is_melee:
		return 2
	var weapon_type := weapon.weapon_type.to_lower()
	if weapon_type == "sidearm" or weapon_type == "pistol":
		return 1
	return 0

func get_weapon_by_name(weapon_name: String) -> WeaponData:
	var weapon_slots: Array = _controller.get("weapon_slots")
	for weapon_value in weapon_slots:
		var weapon := weapon_value as WeaponData
		if weapon and weapon.weapon_name == weapon_name:
			return weapon
	return null

func drop_slot_weapon(slot: int) -> void:
	if slot == 2:
		return
	var weapon_slots: Array = _controller.get("weapon_slots")
	var weapon_to_drop := weapon_slots[slot] as WeaponData
	if not weapon_to_drop or weapon_to_drop.is_melee:
		return

	var agent := _controller.get("agent") as BaseAgent
	var muzzle := _controller.get("muzzle") as Marker2D
	var drop_position: Vector2 = muzzle.global_position if muzzle else agent.global_position
	var direction := (agent.get_global_mouse_position() - agent.global_position).normalized()
	var current_slot := int(_controller.get("current_weapon_slot"))
	var dropped_ammo := int(_controller.get("ammo_in_magazine")) if slot == current_slot else int(_controller.get("slot_ammo")[slot])
	var dropped_reserve := int(_controller.get("reserve_ammo")) if slot == current_slot else int(_controller.get("slot_reserve_ammo")[slot])
	spawn_dropped_weapon(weapon_to_drop, drop_position, direction, dropped_ammo, dropped_reserve)
	weapon_slots[slot] = null
	_controller.get("slot_ammo")[slot] = 0
	_controller.get("slot_reserve_ammo")[slot] = 0
	_controller.get("slot_initialized")[slot] = false

func spawn_dropped_weapon(
	weapon: WeaponData,
	drop_position: Vector2,
	direction: Vector2,
	dropped_ammo: int,
	dropped_reserve: int
) -> void:
	var agent := _controller.get("agent") as BaseAgent
	if not weapon or not agent:
		return
	if _controller.get_multiplayer().has_multiplayer_peer():
		var peer_id := agent.get_multiplayer_authority()
		if _controller.get_multiplayer().is_server():
			NetworkManager.spawn_dropped_weapon.rpc(
				peer_id, weapon.resource_path, drop_position, direction,
				dropped_ammo, dropped_reserve
			)
		else:
			NetworkManager.request_dropped_weapon.rpc_id(
				1, peer_id, weapon.resource_path, drop_position, direction,
				dropped_ammo, dropped_reserve
			)
		return

	var dropped := preload("res://scenes/weapons/dropped_weapon.tscn").instantiate() as DroppedWeapon
	agent.get_parent().add_child(dropped)
	dropped.init_weapon(weapon, drop_position, direction, dropped_ammo, dropped_reserve)
