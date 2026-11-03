class_name MovementController
extends Node

@export_group("Audio")
@export_range(0.1, 2.0, 0.05) var running_step_interval: float = 0.38
@export_range(0.1, 2.0, 0.05) var walking_step_interval: float = 0.52

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var step_timer := 0.0
var slow_zone_sources: Dictionary = {}

func set_slow_zone_active(source_id: int, active: bool) -> void:
	if source_id <= 0:
		return
	if active:
		slow_zone_sources[source_id] = true
	else:
		slow_zone_sources.erase(source_id)
	if agent and agent.has_local_authority():
		var hud := _get_game_hud()
		if hud:
			hud.set_slow_state(not slow_zone_sources.is_empty())

func process_movement(delta: float) -> void:
	if not agent:
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_max_speed: float = agent.run_speed
	if not slow_zone_sources.is_empty():
		current_max_speed *= 0.5
	if agent.weapon_controller and agent.weapon_controller.current_weapon:
		current_max_speed *= agent.weapon_controller.current_weapon.run_speed_multiplier
		if agent.weapon_controller.is_aiming():
			current_max_speed *= agent.weapon_controller.current_weapon.aim_move_speed_multiplier
	if Input.is_action_pressed("walk"):
		current_max_speed *= agent.walk_speed_ratio

	if input_vector != Vector2.ZERO:
		agent.velocity = agent.velocity.move_toward(input_vector * current_max_speed, agent.acceleration * delta)
	else:
		agent.velocity = agent.velocity.move_toward(Vector2.ZERO, agent.friction * delta)
	agent.move_and_slide()
	_process_footsteps(delta, current_max_speed)

func _get_game_hud() -> GameHud:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return null
	var hud := current_scene.get_node_or_null("HUD") as GameHud
	if not hud:
		hud = current_scene.find_child("GameHud", true, false) as GameHud
	return hud

func _process_footsteps(delta: float, current_max_speed: float) -> void:
	if agent.velocity.length() < 8.0:
		step_timer = 0.0
		return

	step_timer -= delta
	if step_timer > 0.0:
		return

	agent.play_footstep_sfx()
	step_timer = (
		walking_step_interval
		if current_max_speed < agent.run_speed * 0.8
		else running_step_interval
	)
