extends Node

const ANCHOR_SCENE: PackedScene = preload("res://scenes/agents/phoenix/run_it_back.tscn")
const ULTIMATE_DURATION := 10.0
const RETURN_DURATION := 1.0
const RETURN_FADE_HALF_DURATION := RETURN_DURATION * 0.5
const RETURN_MOVEMENT_LOCK_DURATION := 0.5
const HURT_AUDIO_QUIET_PERIOD := 0.2

@export_group("Audio")
@export var cast_audio: AudioCue
@export var voice_audio: AudioCue
@export var finish_audio: AudioCue
@export var hurt_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var time_remaining := 0.0
var is_active := false
var active_anchor: StaticBody2D
var return_position := Vector2.ZERO
var shield_at_activation := 0.0
var hurt_audio_timer: Timer

func _ready() -> void:
	hurt_audio_timer = Timer.new()
	hurt_audio_timer.one_shot = true
	hurt_audio_timer.wait_time = HURT_AUDIO_QUIET_PERIOD
	hurt_audio_timer.timeout.connect(_play_hurt_audio_now)
	add_child(hurt_audio_timer)

func reset_for_new_round() -> void:
	if not is_active:
		return
	is_active = false
	time_remaining = 0.0
	if is_instance_valid(active_anchor):
		active_anchor.queue_free()
	active_anchor = null
	if agent:
		agent.is_movement_locked = false
		_hide_hud_timer()
		agent.set_ultimate_state(agent.has_ultimate_charge(), false)

func is_ultimate_active() -> bool:
	return is_active

func schedule_hurt_audio_locally() -> void:
	if not agent or not agent.has_local_authority():
		return
	if agent.is_dead or agent.health_component.current_health <= 0.0:
		hurt_audio_timer.stop()
		return
	hurt_audio_timer.start()

func _play_hurt_audio_now() -> void:
	if (
		agent
		and agent.has_local_authority()
		and not agent.is_dead
		and agent.health_component.current_health > 0.0
	):
		AudioManager.play_global_cue(hurt_audio)

func _input(event: InputEvent) -> void:
	if (
		not agent
		or not agent.has_local_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or is_active
		or not agent.agent_data
		or not event.is_action_pressed(agent.agent_data.ultimate_input_action)
	):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if not agent.has_ultimate_charge():
		get_viewport().set_input_as_handled()
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_ultimate_rpc.rpc_id(1)
	elif multiplayer.has_multiplayer_peer():
		start_ultimate_rpc.rpc(
			agent.get_multiplayer_authority(),
			agent.global_position,
			ULTIMATE_DURATION
		)
	else:
		_start_ultimate(agent.get_global_position(), ULTIMATE_DURATION, agent.get_multiplayer_authority())
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_active:
		return

	time_remaining = maxf(0.0, time_remaining - delta)

	if time_remaining == 0.0:
		if not multiplayer.has_multiplayer_peer():
			_finish_ultimate(false)
		elif multiplayer.is_server():
			finish_ultimate_rpc.rpc(agent.get_multiplayer_authority(), false)

@rpc("any_peer", "reliable")
func request_ultimate_rpc() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != agent.get_multiplayer_authority():
		return
	if (
		agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or is_active
		or not agent.has_ultimate_charge()
	):
		return
	start_ultimate_rpc.rpc(
		agent.get_multiplayer_authority(),
		agent.global_position,
		ULTIMATE_DURATION
	)

@rpc("any_peer", "call_local", "reliable")
func start_ultimate_rpc(owner_peer_id: int, origin: Vector2, duration: float) -> void:
	if not _rpc_is_from_server():
		return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or is_active
		or not origin.is_finite()
		or not is_finite(duration)
		or duration <= 0.0
	):
		return

	_start_ultimate(origin, duration, owner_peer_id)

func _start_ultimate(origin: Vector2, duration: float, owner_peer_id: int) -> void:
	if not get_tree().current_scene:
		push_error("Cannot start Run It Back without an active scene.")
		return
	if (
		(not multiplayer.has_multiplayer_peer() or multiplayer.is_server())
		and not agent.consume_ultimate_charge()
	):
		return
	is_active = true
	agent.set_ultimate_state(agent.has_ultimate_charge(), true)
	return_position = origin
	shield_at_activation = agent.health_component.current_shield
	time_remaining = duration
	_spawn_anchor(origin, owner_peer_id)
	AudioManager.play_world_cue(cast_audio, origin)
	AudioManager.play_global_cue(voice_audio)
	if agent.has_local_authority():
		_start_hud_timer(duration)

@rpc("any_peer", "call_local", "reliable")
func finish_ultimate_rpc(owner_peer_id: int, restore_activation_health: bool) -> void:
	if not _rpc_is_from_server():
		return
	if owner_peer_id != agent.get_multiplayer_authority() or not is_active:
		return

	_finish_ultimate(restore_activation_health)

func handle_agent_death() -> bool:
	if not is_active:
		return false
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return true
	if has_node("/root/NetworkManager"):
		NetworkManager.report_agent_kill_effect(agent, agent.last_attacker, "Run It Back")
	if multiplayer.has_multiplayer_peer():
		finish_ultimate_rpc.rpc(agent.get_multiplayer_authority(), true)
	else:
		_finish_ultimate(true)
	return true

func _finish_ultimate(restore_activation_health: bool) -> void:
	if not is_active:
		return
	is_active = false
	agent.set_ultimate_state(agent.has_ultimate_charge(), false)
	time_remaining = 0.0
	AudioManager.play_world_cue(finish_audio, agent.global_position)
	agent.is_movement_locked = true
	agent.velocity = Vector2.ZERO
	if restore_activation_health:
		agent.kill_streak_reset_requested.emit()
		agent.health_component.restore_state(
			agent.health_component.max_health,
			shield_at_activation
		)
	if agent.has_local_authority():
		_hide_hud_timer()

	var return_alpha := agent.modulate.a
	var return_tween := agent.create_tween()
	return_tween.tween_property(
		agent,
		"modulate:a",
		0.0,
		RETURN_FADE_HALF_DURATION
	)
	return_tween.tween_callback(func() -> void:
		agent.global_position = return_position
		agent.velocity = Vector2.ZERO
	)
	return_tween.tween_property(
		agent,
		"modulate:a",
		return_alpha,
		RETURN_FADE_HALF_DURATION
	)
	return_tween.tween_callback(_complete_ultimate_return)
	_fade_and_remove_anchor()

func _complete_ultimate_return() -> void:
	agent.set_active_ability("")
	agent.weapon_controller.update_visual(true)
	await get_tree().create_timer(RETURN_MOVEMENT_LOCK_DURATION).timeout
	if is_instance_valid(agent) and is_instance_valid(agent.weapon_controller):
		agent.is_movement_locked = false

func _rpc_is_from_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	var sender_id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		return sender_id == 0 or sender_id == 1
	return sender_id == 1

func _spawn_anchor(origin: Vector2, owner_peer_id: int) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		push_error("Cannot start Run It Back without an active scene.")
		is_active = false
		return

	active_anchor = ANCHOR_SCENE.instantiate() as StaticBody2D
	active_anchor.name = "RunItBack_%d" % owner_peer_id
	active_anchor.add_to_group("skirmish_round_effects")
	active_anchor.collision_layer = 0
	active_anchor.collision_mask = 0
	current_scene.add_child(active_anchor)
	active_anchor.global_position = origin

func _fade_and_remove_anchor() -> void:
	if not is_instance_valid(active_anchor):
		return
	var anchor_to_remove := active_anchor
	active_anchor = null
	var sprite := anchor_to_remove.get_node_or_null("Sprite2D") as Sprite2D
	if not sprite:
		anchor_to_remove.queue_free()
		return
	var anchor_tween := anchor_to_remove.create_tween()
	anchor_tween.tween_property(
		sprite,
		"modulate:a",
		0.0,
		RETURN_DURATION
	)
	anchor_tween.tween_callback(anchor_to_remove.queue_free)

func _start_hud_timer(duration: float) -> void:
	var hud := _get_local_hud()
	if hud:
		hud.start_ability_timer("RUN IT BACK", duration)

func _hide_hud_timer() -> void:
	var hud := _get_local_hud()
	if hud:
		hud.hide_ability_timer()

func _get_local_hud() -> GameHud:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	if not hud:
		return null
	if not hud.player:
		hud.bind_player()
	return hud if hud.player == agent else null
