extends Node

const ABILITY_ID := "BladeStorm"
const BLADE_SCENE: PackedScene = preload("res://scenes/agents/jett/blade.tscn")
@export_group("Blade Storm")
@export var blade_scene: PackedScene = BLADE_SCENE
@export_range(1, 20, 1) var blade_count: int = 5
@export_range(0.0, 45.0, 0.5, "suffix:°") var right_click_spread_degrees: float = 5.0
@export_range(0.01, 1.0, 0.01, "suffix:s") var equip_duration: float = 0.1
@export_range(0.01, 0.5, 0.01, "suffix:x") var equip_start_scale: float = 0.05
@export var blade_marker_paths: Array[NodePath] = [
	NodePath("Visuals/Blades/Blade"),
	NodePath("Visuals/Blades/Blade2"),
	NodePath("Visuals/Blades/Blade3"),
	NodePath("Visuals/Blades/Blade4"),
	NodePath("Visuals/Blades/Blade5"),
]

@export_group("Audio")
@export var activation_audio: AudioCue
@export var activation_voice_audio: AudioCue
@export var shot_audio: AudioCue
@export var shot5_audio: AudioCue
@export var shot5_voice_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var is_active := false
var blades_thrown := 0
var next_launch_id := 0
var projectiles: Dictionary = {}
var block_fire_until_release := false
var equip_time_remaining := 0.0
var marker_base_scales: Dictionary = {}
var marker_equip_tweens: Dictionary = {}

func _ready() -> void:
	_apply_display(false, blade_count)

func reset_for_new_round() -> void:
	_apply_display(false, blade_count)
	block_fire_until_release = false
	equip_time_remaining = 0.0
	projectiles.clear()

func _input(event: InputEvent) -> void:
	if not _can_use_ultimate() or not agent.has_local_authority():
		return
	if not agent.agent_data:
		return
	if event.is_action_pressed(agent.agent_data.ultimate_input_action):
		if event is InputEventKey and (event as InputEventKey).echo:
			return
		if not is_active and (blades_thrown < blade_count or agent.has_ultimate_charge()):
			_request_activation()
		get_viewport().set_input_as_handled()
		return
	if not is_active or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_request_throw(false)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_request_throw(true)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	equip_time_remaining = maxf(equip_time_remaining - delta, 0.0)
	if (
		block_fire_until_release
		and equip_time_remaining <= 0.0
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	):
		block_fire_until_release = false

func blocks_weapon_input() -> bool:
	return is_active or block_fire_until_release

func _can_use_ultimate() -> bool:
	return (
		agent != null
		and not agent.is_dead
		and not agent.shop_open
		and not agent.agent_select_open
		and not agent.is_lobby_locked
		and not agent.is_match_preparing
	)

func _request_activation() -> void:
	if not _can_use_ultimate():
		return
	if blades_thrown >= blade_count and not agent.has_ultimate_charge():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_activation_rpc.rpc_id(1)
	else:
		_start_ultimate()

func _start_ultimate() -> void:
	if not _can_use_ultimate() or is_active:
		return
	var resuming_ultimate := blades_thrown < blade_count
	if not resuming_ultimate and not agent.has_ultimate_charge():
		return
	if not resuming_ultimate:
		blades_thrown = 0
	if agent.weapon_controller:
		agent.weapon_controller.aiming = false
		agent.weapon_controller.aim_level = 0
	_play_equip_audio()
	if not resuming_ultimate:
		_play_activation_voice_audio()
	is_active = true
	equip_time_remaining = equip_duration
	block_fire_until_release = true
	_update_display()

func _end_ultimate_local() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_apply_display(false, blades_thrown)
		request_end_ultimate_rpc.rpc_id(1)
	else:
		_suspend_ultimate()

func end_for_weapon_switch() -> void:
	if is_active:
		_end_ultimate_local()

func _end_ultimate() -> void:
	is_active = false
	blades_thrown = blade_count
	block_fire_until_release = true
	agent.consume_ultimate_charge()
	_update_display()

func _suspend_ultimate() -> void:
	if not is_active:
		return
	is_active = false
	block_fire_until_release = true
	_update_display()

func _request_throw(throw_all: bool) -> void:
	if (
		not _can_use_ultimate()
		or not is_active
		or equip_time_remaining > 0.0
		or blades_thrown >= blade_count
	):
		return
	var direction := agent.get_global_mouse_position() - agent.global_position
	if direction.is_zero_approx() or not direction.is_finite():
		return
	direction = direction.normalized()
	# Las dagas individuales siempre apuntan exactamente al cursor, incluso durante Updraft.
	block_fire_until_release = true
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_throw_rpc.rpc_id(1, direction, throw_all)
	else:
		_throw_authoritatively(direction, throw_all)

func _throw_authoritatively(direction: Vector2, throw_all: bool) -> void:
	if (
		not _can_use_ultimate()
		or not is_active
		or equip_time_remaining > 0.0
		or not direction.is_finite()
		or direction.is_zero_approx()
	):
		return
	var count := blade_count - blades_thrown if throw_all else 1
	if count <= 0:
		return
	var start_position := agent.global_position + direction.normalized() * 8.0
	if multiplayer.has_multiplayer_peer():
		sync_throw_audio_rpc.rpc(
			agent.get_multiplayer_authority(),
			start_position,
			throw_all
		)
	else:
		_play_throw_audio(start_position, throw_all)
	for index in range(count):
		var shot_direction := direction.normalized()
		if throw_all:
			var centered_index := float(index) - (float(count) - 1.0) * 0.5
			shot_direction = shot_direction.rotated(
				deg_to_rad(centered_index * right_click_spread_degrees)
			)
		_launch_dagger(start_position, shot_direction, not throw_all)
	blades_thrown += count
	_update_display()
	if blades_thrown >= blade_count:
		_end_ultimate()

func _launch_dagger(start_position: Vector2, direction: Vector2, refill_on_kill: bool) -> void:
	next_launch_id += 1
	if multiplayer.has_multiplayer_peer():
		sync_blade_launch_rpc.rpc(
			agent.get_multiplayer_authority(),
			next_launch_id,
			start_position,
			direction,
			refill_on_kill
		)
	else:
		_spawn_blade_projectile(next_launch_id, start_position, direction, refill_on_kill)

func _spawn_blade_projectile(
	launch_id: int,
	start_position: Vector2,
	direction: Vector2,
	refill_on_kill: bool
) -> void:
	if launch_id <= 0 or not start_position.is_finite() or not direction.is_finite():
		return
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var blade := blade_scene.instantiate() as Area2D if blade_scene else null
	if not blade:
		return
	blade.name = "BladeProjectile_%d_%d" % [agent.get_multiplayer_authority(), launch_id]
	blade.add_to_group("skirmish_round_effects")
	current_scene.add_child(blade)
	blade.global_position = start_position
	blade.set("launch_id", launch_id)
	blade.call(
		"launch",
		agent,
		self,
		direction,
		refill_on_kill,
		multiplayer.has_multiplayer_peer() and not multiplayer.is_server(),
		agent.agent_data.agent_color
	)
	projectiles[launch_id] = blade

func _play_equip_audio() -> void:
	var owner_peer_id := agent.get_multiplayer_authority()
	if multiplayer.has_multiplayer_peer():
		if activation_audio and activation_audio.stream:
			if owner_peer_id == 1:
				AudioManager.play_local_cue(activation_audio, &"jett_bladestorm")
			else:
				sync_activation_local_audio_rpc.rpc_id(owner_peer_id)
		return
	if activation_audio and activation_audio.stream:
		AudioManager.play_local_cue(activation_audio, &"jett_bladestorm")

func _play_activation_voice_audio() -> void:
	if activation_voice_audio and activation_voice_audio.stream:
		AudioManager.play_global_cue(activation_voice_audio)

func _play_throw_audio(world_position: Vector2, throw_all: bool) -> void:
	var ranged_audio := shot5_audio if throw_all else shot_audio
	if ranged_audio and ranged_audio.stream:
		AudioManager.play_world_cue(ranged_audio, world_position)
	if throw_all and agent.has_local_authority() and shot5_voice_audio and shot5_voice_audio.stream:
		AudioManager.play_local_cue(shot5_voice_audio, &"jett_bladestorm_shot5_voice")

func _update_display() -> void:
	if multiplayer.has_multiplayer_peer():
		sync_display_rpc.rpc(
			agent.get_multiplayer_authority(), is_active, blades_thrown
		)
	else:
		_apply_display(is_active, blades_thrown)

func _apply_display(active: bool, thrown: int) -> void:
	var was_active := is_active
	is_active = active
	blades_thrown = clampi(thrown, 0, blade_count)
	if agent:
		agent.set_ultimate_state(agent.has_ultimate_charge(), active)
	if was_active and not active:
		block_fire_until_release = true
	if not was_active and active:
		equip_time_remaining = equip_duration
		block_fire_until_release = true
	if agent and agent.weapon_controller:
		agent.weapon_controller.set_weapon_hidden_by_ability(active)
		var hud := _get_local_hud()
		if hud:
			hud.set_blade_storm_equipped(active)
		if was_active != active:
			var hud_slot: int = -1 if active else agent.weapon_controller.current_weapon_slot
			agent.weapon_controller.weapon_changed.emit(
				agent.weapon_controller.current_weapon,
				hud_slot
			)

	var visible_indices: Array[int] = []
	if active:
		var default_patterns: Dictionary = {
			5: {
				0: [0, 1, 2, 3, 4],
				1: [0, 1, 3, 4],
				2: [0, 2, 4],
				3: [0, 4],
				4: [4],
			},
		}
		if default_patterns.has(blade_count):
			var pattern: Array = default_patterns[blade_count].get(blades_thrown, [])
			for visible_index in pattern:
				visible_indices.append(int(visible_index))
		else:
			for index in range(blade_count - blades_thrown):
				visible_indices.append(index)
	for index in range(blade_marker_paths.size()):
		var marker := agent.get_node_or_null(blade_marker_paths[index]) as Area2D
		if marker:
			var should_be_visible := index in visible_indices
			var marker_id := marker.get_instance_id()
			if not marker_base_scales.has(marker_id):
				marker_base_scales[marker_id] = marker.scale
			if should_be_visible and not marker.visible:
				_equip_blade_marker(marker, marker_id)
			elif not should_be_visible and marker.visible:
				_cancel_blade_marker_equip(marker_id)
				marker.scale = marker_base_scales[marker_id]
				marker.visible = false

func is_ultimate_active() -> bool:
	return is_active

func _equip_blade_marker(marker: Area2D, marker_id: int) -> void:
	_cancel_blade_marker_equip(marker_id)
	var base_scale: Vector2 = marker_base_scales[marker_id]
	marker.visible = true
	marker.scale = base_scale * equip_start_scale
	var tween := marker.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(marker, "scale", base_scale, equip_duration)
	tween.tween_callback(func() -> void: marker_equip_tweens.erase(marker_id))
	marker_equip_tweens[marker_id] = tween

func _cancel_blade_marker_equip(marker_id: int) -> void:
	var tween := marker_equip_tweens.get(marker_id) as Tween
	if tween and tween.is_running():
		tween.kill()
	marker_equip_tweens.erase(marker_id)

func _get_local_hud() -> GameHud:
	var scene := get_tree().current_scene
	if not scene:
		return null
	var hud := scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = scene.find_child("GameHud", true, false) as GameHud
	if hud and hud.player == agent:
		return hud
	return null

func award_dagger_kill() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	is_active = true
	blades_thrown = 0
	block_fire_until_release = false
	_update_display()

@rpc("any_peer", "reliable")
func request_activation_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if (
		multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority()
		or not _can_use_ultimate()
	):
		return
	_start_ultimate()

@rpc("any_peer", "reliable")
func request_end_ultimate_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority() or not is_active:
		return
	_suspend_ultimate()

@rpc("any_peer", "reliable")
func request_throw_rpc(direction: Vector2, throw_all: bool) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	_throw_authoritatively(direction, throw_all)

@rpc("authority", "call_remote", "reliable")
func sync_activation_local_audio_rpc() -> void:
	if (
		not multiplayer.has_multiplayer_peer()
		or multiplayer.is_server()
		or multiplayer.get_remote_sender_id() != 1
		or not agent.has_local_authority()
		or not activation_audio
		or not activation_audio.stream
	):
		return
	AudioManager.play_local_cue(activation_audio, &"jett_bladestorm")

@rpc("any_peer", "call_local", "reliable")
func sync_throw_audio_rpc(owner_peer_id: int, world_position: Vector2, throw_all: bool) -> void:
	if not _rpc_is_from_server():
		return
	if owner_peer_id != agent.get_multiplayer_authority() or not world_position.is_finite():
		return
	_play_throw_audio(world_position, throw_all)

@rpc("authority", "call_local", "reliable")
func sync_blade_launch_rpc(
	owner_peer_id: int,
	launch_id: int,
	start_position: Vector2,
	direction: Vector2,
	refill_on_kill: bool
) -> void:
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	next_launch_id = maxi(next_launch_id, launch_id)
	_spawn_blade_projectile(launch_id, start_position, direction, refill_on_kill)

@rpc("authority", "call_local", "reliable")
func sync_display_rpc(owner_peer_id: int, active: bool, thrown: int) -> void:
	if owner_peer_id != agent.get_multiplayer_authority():
		return
	_apply_display(active, thrown)

@rpc("authority", "call_local", "reliable")
func sync_blade_impact_rpc(launch_id: int, impact_position: Vector2) -> void:
	if not impact_position.is_finite():
		return
	var blade := projectiles.get(launch_id) as Node2D
	if blade and blade.has_method("create_trail"):
		blade.call("create_trail", impact_position)
		blade.queue_free()
	projectiles.erase(launch_id)

func _rpc_is_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender_id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1
