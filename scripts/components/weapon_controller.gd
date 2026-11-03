extends Node

signal weapon_changed(weapon: WeaponData, slot: int)

const BASE_FIRST_SHOT_SPREAD_DEGREES := 0.25
const BASE_WALK_SPREAD_DEGREES := 15.0
const BASE_RUN_SPREAD_DEGREES := 30.0
const WeaponLoadoutServiceScript = preload("res://scripts/components/weapon_loadout_service.gd")
const WeaponPresentationServiceScript = preload("res://scripts/components/weapon_presentation_service.gd")
const WeaponSelectionServiceScript = preload("res://scripts/components/weapon_selection_service.gd")

@export var weapon_slots: Array[WeaponData] = []

@onready var agent = get_parent().get_parent()
@onready var weapon_sprite: Sprite2D = get_node_or_null("../../Visuals/BodySprite/WeaponPivot/WeaponSprite") as Sprite2D
@onready var weapon_pivot: Node2D = get_node_or_null("../../Visuals/BodySprite/WeaponPivot") as Node2D
@onready var muzzle: Marker2D = get_node_or_null("../../Visuals/BodySprite/WeaponPivot/Muzzle") as Marker2D

var current_weapon: WeaponData
var weapon_sprite_base_scale := Vector2.ONE
var weapon_sprite_base_rotation := 0.0
var weapon_pivot_base_rotation := 0.0
var equip_tween: Tween
var reload_tween: Tween
var melee_attack_tween: Tween
var is_equipping := false
var current_weapon_slot := 0
var ammo_in_magazine := 0
var reserve_ammo := 0
var suppress_shoot_until_physics_frame := -1
var wait_for_shoot_release := false
var aiming := false
var aim_level := 0
var weapon_hidden_by_ability := false

var shoot_cooldown := 0.0
var secondary_fire_cooldown_remaining := 0.0
var reload_timer := 0.0
var melee_light_cooldown_remaining := 0.0
var melee_heavy_cooldown_remaining := 0.0
var recoil_degrees := 0.0
var slot_ammo: Array[int] = [0, 0, 0]
var slot_reserve_ammo: Array[int] = [0, 0, 0]
var slot_initialized: Array[bool] = [false, false, false]
var infinite_ammo_enabled := false
var _loadout_service: Object
var _presentation_service: Object
var _selection_service: Object

func is_aiming() -> bool:
	return (
		agent
		and current_weapon
		and current_weapon.can_aim
		and aiming
	)

func get_current_aim_zoom() -> float:
	if not is_aiming() or not current_weapon:
		return 1.0
	if aim_level >= 2 and current_weapon.aim_zoom_secondary > 1.0:
		return current_weapon.aim_zoom_secondary
	return current_weapon.aim_zoom

func reset_after_respawn() -> void:
	reload_timer = 0.0
	shoot_cooldown = 0.0
	secondary_fire_cooldown_remaining = 0.0
	melee_light_cooldown_remaining = 0.0
	melee_heavy_cooldown_remaining = 0.0
	stop_melee_attack_animation()
	recoil_degrees = 0.0
	aiming = false
	aim_level = 0
	if current_weapon and not current_weapon.is_melee:
		ammo_in_magazine = current_weapon.magazine_size
		reserve_ammo = current_weapon.reserve_ammo
		slot_ammo[current_weapon_slot] = ammo_in_magazine
		slot_reserve_ammo[current_weapon_slot] = reserve_ammo
	stop_reload_animation()
	update_visual()
	weapon_changed.emit(current_weapon, current_weapon_slot)
	if multiplayer.has_multiplayer_peer() and agent.has_local_authority():
		var peer_id: int = agent.get_multiplayer_authority()
		if multiplayer.is_server():
			NetworkManager.sync_player_weapon.rpc(peer_id, current_weapon_slot)
		else:
			NetworkManager.request_weapon_sync.rpc_id(1, peer_id, current_weapon_slot)

func _ready() -> void:
	_loadout_service = WeaponLoadoutServiceScript.new()
	_loadout_service.call("setup", self)
	_presentation_service = WeaponPresentationServiceScript.new()
	_presentation_service.call("setup", self)
	_selection_service = WeaponSelectionServiceScript.new()
	_selection_service.call("setup", self)
	if weapon_slots.size() < 3:
		weapon_slots.resize(3)
	if not weapon_slots[1]:
		weapon_slots[1] = preload("res://resources/weapons/classic.tres")
	if not weapon_slots[2]:
		weapon_slots[2] = preload("res://resources/weapons/knife.tres")
	weapon_sprite_base_scale = weapon_sprite.scale if weapon_sprite else Vector2.ONE
	weapon_sprite_base_rotation = weapon_sprite.rotation if weapon_sprite else 0.0
	weapon_pivot_base_rotation = weapon_pivot.rotation if weapon_pivot else 0.0
	select_weapon_slot(1, false, false)
	call_deferred("update_visual")

func process_weapon(delta: float) -> void:
	if agent.infinite_ammo_enabled and current_weapon and not current_weapon.is_melee:
		_refill_infinite_ammo()
	shoot_cooldown = maxf(0.0, shoot_cooldown - delta)
	secondary_fire_cooldown_remaining = maxf(0.0, secondary_fire_cooldown_remaining - delta)
	melee_light_cooldown_remaining = maxf(0.0, melee_light_cooldown_remaining - delta)
	melee_heavy_cooldown_remaining = maxf(0.0, melee_heavy_cooldown_remaining - delta)
	if current_weapon:
		recoil_degrees = move_toward(
			recoil_degrees,
			0.0,
			current_weapon.recoil_recovery_speed * delta
		)
	if reload_timer > 0.0:
		reload_timer = maxf(0.0, reload_timer - delta)
		if reload_timer == 0.0:
			finish_reload()
	if agent.infinite_ammo_enabled and current_weapon and not current_weapon.is_melee:
		_refill_infinite_ammo()

	handle_shooting()
	if agent.infinite_ammo_enabled and current_weapon and not current_weapon.is_melee:
		_refill_infinite_ammo()

func set_infinite_ammo_enabled(enabled: bool) -> void:
	infinite_ammo_enabled = enabled
	if infinite_ammo_enabled:
		_refill_infinite_ammo()
	else:
		_update_ammo_ui()

func _refill_infinite_ammo() -> void:
	if not current_weapon or current_weapon.is_melee:
		return
	ammo_in_magazine = current_weapon.magazine_size
	reserve_ammo = current_weapon.reserve_ammo
	slot_ammo[current_weapon_slot] = ammo_in_magazine
	slot_reserve_ammo[current_weapon_slot] = reserve_ammo
	_update_ammo_ui()

func _update_ammo_ui() -> void:
	if agent and agent.has_method("update_local_weapon_hud"):
		agent.call("update_local_weapon_hud")

func _input(event: InputEvent) -> void:
	if agent and (not agent.has_local_authority() or agent.shop_open):
		return
	if _abilities_block_weapon_input():
		return
	if event.is_action_pressed("aim"):
		toggle_aiming()
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	if agent and (not agent.has_local_authority() or agent.shop_open):
		return
	if _abilities_block_weapon_input():
		if event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_1:
					select_weapon_slot(0)
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					select_weapon_slot(1)
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					select_weapon_slot(2)
					get_viewport().set_input_as_handled()
					return
		if event is InputEventMouseButton:
			var blocked_mouse_event := event as InputEventMouseButton
			if blocked_mouse_event.pressed:
				match blocked_mouse_event.button_index:
					MOUSE_BUTTON_WHEEL_UP:
						_cycle_weapon_slot(1)
						get_viewport().set_input_as_handled()
						return
					MOUSE_BUTTON_WHEEL_DOWN:
						_cycle_weapon_slot(-1)
						get_viewport().set_input_as_handled()
						return
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		match mouse_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cycle_weapon_slot(1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_weapon_slot(-1)
				get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.physical_keycode:
		KEY_1:
			select_weapon_slot(0)
		KEY_2:
			select_weapon_slot(1)
		KEY_3:
			select_weapon_slot(2)

func toggle_aiming() -> void:
	_selection_service.call("toggle_aiming")

func select_weapon_slot(slot: int, sync_network: bool = true, animate_equip: bool = true) -> void:
	_selection_service.call("select_weapon_slot", slot, sync_network, animate_equip)

func _cycle_weapon_slot(direction: int) -> void:
	_selection_service.call("cycle_weapon_slot", direction)

func handle_shooting() -> void:
	if wait_for_shoot_release:
		if Input.is_action_pressed("shoot"):
			return
		wait_for_shoot_release = false
	if (
		not current_weapon
		or is_equipping
		or agent.shop_open
		or agent.agent_select_open
		or agent.training_menu_open
		or _abilities_block_weapon_input()
		or Engine.get_physics_frames() <= suppress_shoot_until_physics_frame
	):
		return
	if current_weapon.is_melee:
		var heavy_melee_attack := Input.is_action_just_pressed("aim")
		if heavy_melee_attack:
			if melee_heavy_cooldown_remaining == 0.0:
				attack_melee(true)
		elif Input.is_action_just_pressed("shoot") and melee_light_cooldown_remaining == 0.0:
			attack_melee()
		return
	if reload_timer > 0.0 or shoot_cooldown > 0.0:
		return

	var use_secondary_fire: bool = (
		current_weapon.secondary_fire_pellets > 1
		and Input.is_action_just_pressed("aim")
	)
	var wants_to_shoot: bool = use_secondary_fire
	if not use_secondary_fire:
		wants_to_shoot = (
			Input.is_action_pressed("shoot")
			if current_weapon.is_automatic
			else Input.is_action_just_pressed("shoot")
		)
	if not wants_to_shoot:
		return
	if use_secondary_fire and secondary_fire_cooldown_remaining > 0.0:
		return
	var ammo_cost: int = (
		current_weapon.secondary_fire_ammo_cost
		if use_secondary_fire
		else 1
	)
	if ammo_in_magazine < ammo_cost:
		start_reload()
		return

	var fire_rate: float = current_weapon.fire_rate
	if is_aiming():
		fire_rate *= current_weapon.aim_fire_rate_multiplier
	shoot_cooldown = 1.0 / fire_rate if fire_rate > 0.0 else 0.1
	if use_secondary_fire:
		secondary_fire_cooldown_remaining = current_weapon.secondary_fire_cooldown
		fire_bullet(
			current_weapon.secondary_fire_pellets,
			current_weapon.secondary_pellet_spread_degrees,
			true
		)
	else:
		fire_bullet()
	ammo_in_magazine -= ammo_cost
	if ammo_in_magazine == 0:
		start_reload()

func suppress_shoot_until_released() -> void:
	suppress_shoot_until_physics_frame = Engine.get_physics_frames() + 1
	wait_for_shoot_release = true
	shoot_cooldown = maxf(shoot_cooldown, 0.1)

func _abilities_block_weapon_input() -> bool:
	for component in agent.get_node("Components").get_children():
		if component.has_method("blocks_weapon_input") and component.blocks_weapon_input():
			return true
	return false

func attack_melee(heavy_attack: bool = false) -> void:
	if heavy_attack:
		melee_heavy_cooldown_remaining = current_weapon.melee_heavy_cooldown
	else:
		melee_light_cooldown_remaining = current_weapon.melee_light_cooldown
	agent.play_melee_sfx(heavy_attack)
	var direction: Vector2 = (agent.get_global_mouse_position() - agent.global_position).normalized()
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		agent.global_position,
		agent.global_position + direction * current_weapon.melee_range
	)
	query.collision_mask = 16
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [agent.get_rid()]

	var hit: Dictionary = agent.get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		var damage: float = (
			current_weapon.melee_heavy_damage
			if heavy_attack
			else current_weapon.melee_light_damage
		)
		DamageSystem.apply_hit(
			hit.collider, damage, agent, current_weapon.weapon_name, true, int(hit.get("shape", -1))
		)

func animate_melee_attack(heavy_attack: bool) -> void:
	_presentation_service.call("animate_melee_attack", heavy_attack)

func stop_melee_attack_animation() -> void:
	_presentation_service.call("stop_melee_attack_animation")

func fire_bullet(
	pellet_count_override: int = 0,
	pellet_spread_override: float = -1.0,
	is_secondary_fire: bool = false
) -> void:
	if _is_blade_storm_active():
		return
	var from_pos: Vector2 = muzzle.global_position if muzzle else agent.global_position
	var direction: Vector2 = (agent.get_global_mouse_position() - from_pos).normalized()
	var spread: float = BASE_FIRST_SHOT_SPREAD_DEGREES
	var walk_speed: float = agent.run_speed * agent.walk_speed_ratio
	var current_speed: float = agent.velocity.length()

	if current_speed > walk_speed + 10.0:
		spread = BASE_RUN_SPREAD_DEGREES
	elif current_speed > 10.0:
		spread = BASE_WALK_SPREAD_DEGREES
	var recoil_variation: float = randf_range(
		-current_weapon.recoil_randomness_degrees,
		current_weapon.recoil_randomness_degrees
	)
	var recoil_multiplier: float = current_weapon.aim_recoil_multiplier if is_aiming() else 1.0
	recoil_multiplier *= _get_ability_recoil_multiplier()
	var ability_spread := _get_ability_spread_degrees()
	var pellet_spread: float = (
		current_weapon.pellet_spread_degrees
		if pellet_spread_override < 0.0
		else pellet_spread_override
	)
	var total_spread: float = (
		spread
		+ pellet_spread
		+ (current_weapon.hipfire_spread_degrees if not is_aiming() else 0.0)
		+ ability_spread
		+ recoil_degrees * recoil_multiplier
		+ recoil_variation * recoil_multiplier
	)
	recoil_degrees = minf(
		recoil_degrees + current_weapon.recoil_per_shot_degrees * recoil_multiplier,
		current_weapon.max_recoil_degrees
	)
	var pellet_count: int = (
		maxi(current_weapon.pellets_per_shot, 1)
		if pellet_count_override <= 0
		else pellet_count_override
	)
	for _pellet_index in pellet_count:
		var pellet_direction: Vector2 = direction.rotated(
			deg_to_rad(randf_range(-total_spread, total_spread))
		)
		spawn_bullet(from_pos, pellet_direction, _pellet_index == 0, is_secondary_fire)

func _get_ability_recoil_multiplier() -> float:
	if _is_blade_storm_active():
		return 1.0
	var multiplier := 1.0
	for component in agent.get_node("Components").get_children():
		if component.has_method("get_weapon_recoil_multiplier"):
			multiplier *= float(component.call("get_weapon_recoil_multiplier"))
	return multiplier

func _is_blade_storm_active() -> bool:
	var blade_storm := agent.get_node_or_null("Components/BladeStormAbility")
	return blade_storm != null and bool(blade_storm.get("is_active"))

func _get_ability_spread_degrees() -> float:
	if _is_blade_storm_active():
		return 0.0
	var spread := 0.0
	for component in agent.get_node("Components").get_children():
		if component.has_method("get_weapon_spread_degrees"):
			spread += float(component.call("get_weapon_spread_degrees"))
	return spread

func spawn_bullet(
	from_pos: Vector2,
	direction: Vector2,
	play_shot_sound: bool = false,
	is_secondary_fire: bool = false
) -> void:
	var shot_audio: AudioCue = (
		current_weapon.secondary_shot_audio
		if is_secondary_fire and current_weapon.secondary_shot_audio
		else current_weapon.shot_audio
	)
	if (
		play_shot_sound
		and not is_secondary_fire
		and current_weapon.shot_local_audio
		and agent.has_local_authority()
	):
		AudioManager.play_global_cue(current_weapon.shot_local_audio)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			agent.spawn_network_bullet.rpc(
				from_pos,
				direction,
				current_weapon.wall_penetration,
				current_weapon.tracer_enabled,
				current_weapon.weapon_name,
				current_weapon.short_range,
				current_weapon.medium_range,
				current_weapon.short_damage,
				current_weapon.medium_damage,
				current_weapon.long_damage,
				play_shot_sound,
				is_secondary_fire
			)
		else:
			agent.request_network_bullet.rpc(
				from_pos,
				direction,
				current_weapon.wall_penetration,
				current_weapon.tracer_enabled,
				current_weapon.weapon_name,
				current_weapon.short_range,
				current_weapon.medium_range,
				current_weapon.short_damage,
				current_weapon.medium_damage,
				current_weapon.long_damage,
				play_shot_sound,
				is_secondary_fire
			)
		return

	if play_shot_sound and (is_secondary_fire or not current_weapon.shot_local_audio):
		AudioManager.play_world_cue(shot_audio, from_pos)

	var bullet_scene: PackedScene = preload("res://scenes/weapons/bullet.tscn")
	var bullet: Bullet = bullet_scene.instantiate() as Bullet
	bullet.init_bullet(
		from_pos,
		direction,
		agent,
		current_weapon.wall_penetration,
		current_weapon.weapon_name,
		current_weapon.short_range,
		current_weapon.medium_range,
		current_weapon.short_damage,
		current_weapon.medium_damage,
		current_weapon.long_damage
	)
	bullet.set_tracer_enabled(current_weapon.tracer_enabled or agent.has_local_authority())
	agent.get_parent().add_child(bullet)

func start_reload() -> void:
	if not current_weapon or current_weapon.is_melee or reload_timer > 0.0:
		return
	if ammo_in_magazine >= current_weapon.magazine_size or reserve_ammo <= 0:
		return
	reload_timer = current_weapon.reload_time
	agent.play_reload_sfx(current_weapon_slot)
	start_reload_animation(reload_timer)

func finish_reload() -> void:
	if not current_weapon or current_weapon.is_melee or reload_timer > 0.0:
		return
	stop_reload_animation()
	var missing_ammo: int = current_weapon.magazine_size - ammo_in_magazine
	var loaded_ammo: int = mini(missing_ammo, reserve_ammo)
	ammo_in_magazine += loaded_ammo
	reserve_ammo -= loaded_ammo

func start_reload_animation(duration: float) -> void:
	_presentation_service.call("start_reload_animation", duration)

func stop_reload_animation() -> void:
	_presentation_service.call("stop_reload_animation")

func drop_current_weapon() -> void:
	_loadout_service.call("drop_current_weapon")

func get_fallback_weapon_slot(excluded_slot: int) -> int:
	return int(_loadout_service.call("get_fallback_weapon_slot", excluded_slot))

func ensure_knife_slot() -> int:
	return int(_loadout_service.call("ensure_knife_slot"))

func apply_shop_weapon(weapon: WeaponData) -> void:
	_loadout_service.call("apply_shop_weapon", weapon)

func try_pickup_weapon() -> void:
	_loadout_service.call("try_pickup_weapon")

func try_auto_pickup_weapon(dropped: DroppedWeapon) -> void:
	_loadout_service.call("try_auto_pickup_weapon", dropped)

func equip_dropped_weapon(dropped: DroppedWeapon) -> void:
	_loadout_service.call("equip_dropped_weapon", dropped)

func get_weapon_slot(weapon: WeaponData) -> int:
	return int(_loadout_service.call("get_weapon_slot", weapon))

func get_weapon_by_name(weapon_name: String) -> WeaponData:
	return _loadout_service.call("get_weapon_by_name", weapon_name) as WeaponData

func drop_slot_weapon(slot: int) -> void:
	_loadout_service.call("drop_slot_weapon", slot)

func spawn_dropped_weapon(weapon: WeaponData, drop_pos: Vector2, direction: Vector2, dropped_ammo: int, dropped_reserve: int) -> void:
	_loadout_service.call("spawn_dropped_weapon", weapon, drop_pos, direction, dropped_ammo, dropped_reserve)

func update_visual(animate_equip: bool = false) -> void:
	_presentation_service.call("update_visual", animate_equip)

func set_weapon_hidden_by_ability(hidden: bool) -> void:
	_presentation_service.call("set_weapon_hidden_by_ability", hidden)

func _finish_equip_animation() -> void:
	_presentation_service.call("_finish_equip_animation")
