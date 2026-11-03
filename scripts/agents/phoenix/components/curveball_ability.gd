extends Node

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/agents/phoenix/curva_ball.tscn")
const METERS_TO_PIXELS: float = WeaponData.PIXELS_PER_METER
const FLASH_OCCLUSION_LAYER: int = 1 << 6

@export_group("Audio")
@export var cast_audio: AudioCue
@export var voice_audio_1: AudioCue
@export var voice_audio_2: AudioCue
@export var active_audio: AudioCue

@export_range(1.0, 30.0, 0.5) var projectile_range_meters: float = 8.0
@export_range(0.1, 2.0, 0.05) var projectile_flight_time: float = 0.45
@export_range(0.0, 180.0, 5.0) var curve_angle_degrees: float = 90.0
@export_range(1.0, 30.0, 0.5) var flash_range_meters: float = 20.0
@export_range(30.0, 360.0, 5.0) var flash_field_of_view_degrees: float = 180.0
@export_range(0.1, 5.0, 0.1) var flash_duration: float = 1.5

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var held_projectile: Area2D
var held_projectile_sprite: Sprite2D
var held_projectile_sprite_base_scale := Vector2.ONE
var is_equipped := false
var cast_pending := false
var next_cast_id := 0
var flashed_indicator: Sprite2D
var flashed_indicator_tween: Tween

func reset_for_new_round() -> void:
	cast_pending = false
	_hide_flashed_indicator()
	_set_equipped(false)

func _ready() -> void:
	flashed_indicator = agent.get_node_or_null("Visuals/Flashed") as Sprite2D
	if not flashed_indicator:
		push_error("BaseAgent is missing the Visuals/Flashed indicator.")
	held_projectile = agent.get_node_or_null("Visuals/CurveballHeld") as Area2D
	if not held_projectile:
		push_error("Curveball held projectile is missing from the agent scene.")
		return
	held_projectile.top_level = true
	held_projectile.monitoring = false
	held_projectile.monitorable = false
	held_projectile_sprite = held_projectile.get_node_or_null("Sprite2D") as Sprite2D
	if not held_projectile_sprite:
		push_error("Curveball held sprite is missing from the agent scene.")
		return
	held_projectile_sprite_base_scale = held_projectile_sprite.scale
	held_projectile.visible = false
	_position_held_projectile()

func _process(_delta: float) -> void:
	if is_equipped:
		_position_held_projectile()
	if agent and (agent.is_dead or agent.shop_open) and is_equipped:
		_set_equipped(false)
	if agent and agent.is_dead:
		_hide_flashed_indicator()

func _input(event: InputEvent) -> void:
	if not agent or not agent.has_local_authority() or agent.is_dead or agent.shop_open or agent.is_match_preparing:
		return

	if not is_equipped or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT and mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if cast_pending:
		return

	var direction := agent.get_global_mouse_position() - _get_muzzle_position()
	if direction.is_zero_approx():
		return
	var curve_sign := -1.0 if mouse_event.button_index == MOUSE_BUTTON_LEFT else 1.0
	_request_cast(direction.normalized(), curve_sign)
	get_viewport().set_input_as_handled()

func blocks_weapon_input() -> bool:
	return is_equipped or cast_pending

@rpc("any_peer", "reliable")
func request_equipped_rpc(equipped: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	if agent.is_dead or agent.shop_open or agent.is_match_preparing:
		return
	_sync_equipped_state(equipped)

@rpc("any_peer", "call_local", "reliable")
func sync_equipped_rpc(owner_peer_id: int, equipped: bool) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	_set_equipped(equipped)

func _sync_equipped_state(equipped: bool) -> void:
	sync_equipped_rpc.rpc(agent.get_multiplayer_authority(), equipped)

func _request_cast(direction: Vector2, curve_sign: float) -> void:
	if cast_pending:
		return
	cast_pending = true
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_cast_rpc.rpc_id(1, direction, curve_sign)
		_set_equipped(false)
	else:
		_launch_projectile(direction, curve_sign)

@rpc("any_peer", "reliable")
func request_cast_rpc(direction: Vector2, curve_sign: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	if (
		agent.is_dead
		or agent.shop_open
		or agent.is_match_preparing
		or not is_equipped
		or not agent.has_ability_charge("Curveball")
		or not direction.is_finite()
		or direction.is_zero_approx()
		or absf(curve_sign) != 1.0
	):
		cast_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	_launch_projectile(direction.normalized(), curve_sign)

@rpc("any_peer", "call_remote", "reliable")
func cast_rejected_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	cast_pending = false
	if (
		agent.has_local_authority()
		and not agent.is_dead
		and not agent.shop_open
		and agent.has_ability_charge("Curveball")
	):
		_set_equipped(true)

func _launch_projectile(direction: Vector2, curve_sign: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if not agent.consume_ability_charge("Curveball"):
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			cast_rejected_rpc.rpc_id(agent.get_multiplayer_authority())
		return
	next_cast_id += 1
	var owner_peer_id := agent.get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	_play_voice_for_owner(owner_peer_id)
	var start_position := _get_muzzle_position()
	cast_pending = false
	agent.set_active_ability("")
	_set_equipped(false)
	agent.weapon_controller.suppress_shoot_until_released()

	if multiplayer.has_multiplayer_peer():
		spawn_projectile_rpc.rpc(
			owner_peer_id,
			next_cast_id,
			start_position,
			direction,
			curve_sign,
			projectile_range_meters * METERS_TO_PIXELS,
			projectile_flight_time,
			curve_angle_degrees
		)
	else:
		_spawn_projectile(
			owner_peer_id,
			next_cast_id,
			start_position,
			direction,
			curve_sign,
			projectile_range_meters * METERS_TO_PIXELS,
			projectile_flight_time,
			curve_angle_degrees
		)

func _play_voice_for_owner(owner_peer_id: int) -> void:
	var voice_index := randi_range(0, 1)
	if not multiplayer.has_multiplayer_peer() or owner_peer_id == 1:
		_play_voice(voice_index)
	elif multiplayer.is_server():
		play_voice_rpc.rpc_id(owner_peer_id, voice_index)
	else:
		push_error("Only the server can route Curveball voice audio.")

@rpc("any_peer", "call_remote", "reliable")
func play_voice_rpc(voice_index: int) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not agent.has_local_authority() or voice_index < 0 or voice_index > 1:
		return
	_play_voice(voice_index)

func _play_voice(voice_index: int) -> void:
	var voice_cue: AudioCue = voice_audio_1 if voice_index == 0 else voice_audio_2
	AudioManager.play_global_cue(voice_cue)

func play_active_audio(world_position: Vector2) -> void:
	AudioManager.play_world_cue(active_audio, world_position)

@rpc("any_peer", "call_local", "reliable")
func spawn_projectile_rpc(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	curve_sign: float,
	travel_distance: float,
	flight_time: float,
	curve_angle: float
) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if (
		not direction.is_finite()
		or direction.is_zero_approx()
		or not is_finite(travel_distance)
		or travel_distance <= 0.0
		or not is_finite(flight_time)
		or flight_time <= 0.0
		or not is_finite(curve_angle)
	):
		return

	next_cast_id = maxi(next_cast_id, cast_id)
	cast_pending = false
	_set_equipped(false)
	agent.weapon_controller.suppress_shoot_until_released()
	_spawn_projectile(
		owner_peer_id,
		cast_id,
		start_position,
		direction.normalized(),
		curve_sign,
		travel_distance,
		flight_time,
		curve_angle
	)

func _spawn_projectile(
	owner_peer_id: int,
	cast_id: int,
	start_position: Vector2,
	direction: Vector2,
	curve_sign: float,
	travel_distance: float,
	flight_time: float,
	curve_angle: float
) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot spawn Curveball without an active scene.")
		return
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	projectile.name = "Curveball_%d_%d" % [owner_peer_id, cast_id]
	projectile.add_to_group("skirmish_round_effects")
	current_scene.add_child(projectile)
	projectile.call(
		"initialize",
		owner_peer_id,
		cast_id,
		start_position,
		direction,
		curve_sign,
		travel_distance,
		flight_time,
		curve_angle,
		self
	)

func apply_flash_at(flash_position: Vector2) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot apply Curveball flash without an active scene.")
		return

	for child in current_scene.get_children():
		if child is BaseAgent:
			var target := child as BaseAgent
			if target.is_ai_dummy:
				if target.is_in_match and not target.is_dead and _can_see_flash(target, flash_position):
					target.apply_flash(flash_duration)
				continue
			if target.is_dead or not _can_see_flash(target, flash_position):
				continue
			var target_ability: Node = target.get_node_or_null(
				"Components/CurveballAbility"
			)
			if not target_ability or not target_ability.has_method("receive_flash_rpc"):
				continue
			var target_peer_id := target.get_multiplayer_authority()
			if multiplayer.has_multiplayer_peer():
				target_ability.rpc("show_flashed_indicator_rpc", target_peer_id, flash_duration)
				if target_peer_id != 1:
					target_ability.rpc_id(
						target_peer_id,
						"receive_flash_rpc",
						flash_duration,
						flash_position
					)
				else:
					target_ability.call("_show_screen_flash", flash_duration, flash_position)
			else:
				target_ability.call("_show_screen_flash", flash_duration, flash_position)

func _can_see_flash(target: Node2D, flash_position: Vector2) -> bool:
	var offset := flash_position - target.global_position
	var distance_limit := flash_range_meters * METERS_TO_PIXELS
	if offset.length() > distance_limit or offset.is_zero_approx():
		return false
	var target_rotation: float
	if target is BaseAgent:
		target_rotation = (target as BaseAgent).visuals.global_rotation
	else:
		return false
	var forward := Vector2.UP.rotated(target_rotation)
	var minimum_dot := cos(deg_to_rad(flash_field_of_view_degrees * 0.5))
	if forward.dot(offset.normalized()) < minimum_dot:
		return false

	var query := PhysicsRayQueryParameters2D.create(target.global_position, flash_position)
	query.collision_mask = 1 | 2 | 4
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [target.get_rid()]
	var space_state := target.get_world_2d().direct_space_state
	if not space_state.intersect_ray(query).is_empty():
		return false

	var ability_wall_query := PhysicsRayQueryParameters2D.create(
		target.global_position,
		flash_position
	)
	ability_wall_query.collision_mask = FLASH_OCCLUSION_LAYER
	ability_wall_query.collide_with_areas = true
	ability_wall_query.collide_with_bodies = false
	return space_state.intersect_ray(ability_wall_query).is_empty()

@rpc("any_peer", "call_remote", "reliable")
func receive_flash_rpc(duration: float, flash_position: Vector2) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_remote_sender_id() != 1:
		return
	if agent.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
	_show_screen_flash(duration, flash_position)

@rpc("any_peer", "call_local", "reliable")
func show_flashed_indicator_rpc(owner_peer_id: int, duration: float) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	if agent.get_multiplayer_authority() != owner_peer_id:
		return
	_show_flashed_indicator(duration)

func _show_screen_flash(duration: float, flash_position: Vector2) -> void:
	if duration <= 0.0 or not is_finite(duration):
		push_error("Flash duration must be a finite, positive value.")
		return
	if not flash_position.is_finite():
		push_error("Flash position must be finite.")
		return

	_show_flashed_indicator(duration)

	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot show Curveball flash without an active scene.")
		return
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	if not hud:
		push_warning("Curveball flash reached a player, but no GameHud was found.")
		return
	hud.show_flash(duration, flash_position)

func _show_flashed_indicator(duration: float) -> void:
	if duration <= 0.0 or not is_finite(duration):
		push_error("Flashed indicator duration must be a finite, positive value.")
		return
	if not flashed_indicator:
		return
	if flashed_indicator_tween and flashed_indicator_tween.is_running():
		flashed_indicator_tween.kill()
	flashed_indicator.visible = true
	flashed_indicator_tween = create_tween()
	flashed_indicator_tween.tween_interval(duration)
	flashed_indicator_tween.tween_callback(_hide_flashed_indicator)

func _hide_flashed_indicator() -> void:
	if flashed_indicator:
		flashed_indicator.visible = false

func _set_equipped(equipped: bool) -> void:
	var was_equipped := is_equipped
	is_equipped = equipped
	if equipped and not was_equipped and agent and agent.has_local_authority():
		AudioManager.play_global_cue(cast_audio)
	if held_projectile:
		if equipped:
			_position_held_projectile()
		if held_projectile_sprite:
			agent.animate_held_ability_equip(
				held_projectile_sprite,
				held_projectile_sprite_base_scale,
				equipped
			)
		held_projectile.visible = equipped
	if not agent or not agent.weapon_controller:
		return
	agent.weapon_controller.aiming = false
	agent.weapon_controller.aim_level = 0
	if equipped:
		if agent.weapon_controller.equip_tween:
			agent.weapon_controller.equip_tween.kill()
		agent.weapon_controller.is_equipping = false
		agent.weapon_controller.weapon_sprite.visible = false
	else:
		agent.weapon_controller.update_visual(true)

func _position_held_projectile() -> void:
	if not is_instance_valid(agent) or not is_instance_valid(held_projectile):
		return
	var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
	if not weapon_pivot:
		push_error("Curveball cannot follow the agent because its WeaponPivot is missing.")
		return
	held_projectile.global_position = weapon_pivot.global_position
	held_projectile.global_rotation = weapon_pivot.global_rotation

func _get_muzzle_position() -> Vector2:
	var muzzle := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot/Muzzle") as Marker2D
	return muzzle.global_position if muzzle else agent.global_position
