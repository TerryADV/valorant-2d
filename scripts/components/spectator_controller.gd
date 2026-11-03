class_name SpectatorController
extends Node

const SpectatorLightMaterial := preload("res://scripts/components/spectator_light_material.gd")

var _agent: Node
var _target: Node

func get_target() -> Node:
	return _target if is_instance_valid(_target) else null

func setup(agent: Node) -> void:
	_agent = agent

func enter() -> void:
	if not _is_spectator_mode():
		return
	_select_target(1)

func exit() -> void:
	_clear_observed_target()
	var camera := _get_camera()
	if camera:
		camera.top_level = false
	if camera:
		camera.enabled = bool(_agent.call("has_local_authority"))
		if camera.enabled:
			camera.make_current()

func process_input(event: InputEvent) -> void:
	if not _is_spectating():
		return
	if event is InputEventMouseButton and event.pressed and not event.is_echo():
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_target(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_select_target(-1)

func _select_target(direction: int) -> void:
	var candidates: Array[Node] = []
	var camera := _get_camera()
	var current_scene := _agent.get_tree().current_scene
	if not current_scene:
		return
	for child in current_scene.get_children():
		if child.has_method("get_deathmatch_id") and child != _agent:
			var candidate := child as Node
			if bool(candidate.get("visible")) and not bool(candidate.get("is_dead")) and (
				not bool(candidate.get("is_ai_dummy")) or bool(candidate.get("is_in_match"))
			) and _is_ally(candidate):
				candidates.append(candidate)
	candidates.sort_custom(func(a: Node, b: Node) -> bool:
		return a.get_multiplayer_authority() < b.get_multiplayer_authority()
	)
	if candidates.is_empty():
		_clear_observed_target()
		if camera:
			camera.enabled = true
			camera.make_current()
		return
	var index := candidates.find(_target)
	index = posmod(index + direction, candidates.size())
	var next_target: Node = candidates[index]
	if next_target != _target:
		_clear_observed_target()
		_target = next_target
		_set_observed_lights(true)
	if not camera:
		return
	camera.enabled = true
	camera.make_current()
	camera.global_position = (_target as Node2D).global_position
	camera.top_level = true
	if not _agent.get_tree().process_frame.is_connected(_follow_target):
		_agent.get_tree().process_frame.connect(_follow_target)

func _follow_target() -> void:
	if _is_spectating() and is_instance_valid(_target):
		var camera := _get_camera()
		if camera:
			camera.global_position = (_target as Node2D).global_position
		if bool(_target.get("is_ai_dummy")):
			SpectatorLightMaterial.set_dummy_lights_visible(_target, true)

func _set_observed_lights(show_lights: bool) -> void:
	if is_instance_valid(_target):
		SpectatorLightMaterial.set_dummy_lights_visible(_target, show_lights)

func _clear_observed_target() -> void:
	_set_observed_lights(false)
	_target = null

func _is_spectating() -> bool:
	return _agent != null and bool(_agent.get("is_dead")) and _is_spectator_mode()

func _is_spectator_mode() -> bool:
	return NetworkManager.is_skirmish_mode() or (
		NetworkManager.is_networked() and not NetworkManager.is_deathmatch_mode()
	)

func _is_ally(candidate: Node) -> bool:
	if NetworkManager.is_skirmish_mode():
		var local_team := NetworkManager.get_skirmish_team_for_peer(
			_agent.get_multiplayer_authority()
		)
		return local_team >= 0 and int(candidate.get("skirmish_team")) == local_team
	return true

func _get_camera() -> Camera2D:
	return _agent.get("player_camera") as Camera2D if _agent else null
