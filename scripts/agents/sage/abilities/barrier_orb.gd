extends Node

const WALL_SCENE: PackedScene = preload("res://scenes/agents/sage/barrier_orb.tscn")
const ABILITY_ID := "BarrierOrb"
const MAX_RANGE := 14.0 * WeaponData.PIXELS_PER_METER
const GHOST_ALPHA := 0.28

@export_group("Audio")
@export var cast_audio: AudioCue
@export var active_audio: AudioCue
@export var voice_audio_1: AudioCue
@export var voice_audio_2: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var barrier_preview: BarrierOrbWall
var next_barrier_id := 0
var preview_rotation_offset := 0.0
var mouse_rotation_active := false
var rotation_anchor_position := Vector2.ZERO
var rotation_anchor_angle := 0.0
var rotation_anchor_aim_angle := 0.0
var mouse_rotation_delta := 0.0
var rotation_start_mouse_position := Vector2.ZERO

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if not event.is_action_pressed(input_action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true
	if agent.active_ability_name == ABILITY_ID:
		preview_rotation_offset = wrapf(preview_rotation_offset + PI / 2.0, -PI, PI)
		_update_preview()
		get_viewport().set_input_as_handled()
		return true
	var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
	if orb_ability and orb_ability.has_method("activate_ability"):
		if bool(orb_ability.call("activate_ability", ABILITY_ID)):
			_play_cast_audio_locally()
	preview_rotation_offset = 0.0
	get_viewport().set_input_as_handled()
	return true

func _process(_delta: float) -> void:
	if not agent:
		return
	var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
	var is_appearing := orb_ability != null and bool(orb_ability.get("is_appearing"))
	if agent.active_ability_name == ABILITY_ID and not is_appearing:
		_update_preview()
	elif is_instance_valid(barrier_preview):
		barrier_preview.queue_free()
		barrier_preview = null

func _input(event: InputEvent) -> void:
	if (
		agent.active_ability_name != ABILITY_ID
		or not agent.has_local_authority()
		or agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
	):
		return
	var orb_ability := agent.get_node_or_null("Components/SageOrbAbility")
	if orb_ability and bool(orb_ability.get("is_appearing")):
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_event.pressed:
				_update_preview()
				if is_instance_valid(barrier_preview):
					rotation_anchor_position = barrier_preview.global_position
					rotation_anchor_angle = barrier_preview.global_rotation
					rotation_anchor_aim_angle = _get_mouse_facing_angle()
					mouse_rotation_delta = 0.0
					rotation_start_mouse_position = get_viewport().get_mouse_position()
			else:
				preview_rotation_offset = wrapf(
					barrier_preview.global_rotation - rotation_anchor_aim_angle,
					-PI,
					PI
				)
			_set_mouse_rotation_active(mouse_event.pressed)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
	elif event is InputEventMouseMotion and mouse_rotation_active:
		mouse_rotation_delta = wrapf(
			mouse_rotation_delta + (event as InputEventMouseMotion).relative.x * 0.01,
			-PI,
			PI
		)
		_update_preview()
		get_viewport().set_input_as_handled()
		return
	else:
		return
	_update_preview()
	if not is_instance_valid(barrier_preview):
		return
	_place_wall()
	get_viewport().set_input_as_handled()

func blocks_weapon_input() -> bool:
	return agent != null and agent.active_ability_name == ABILITY_ID

func reset_for_new_round() -> void:
	preview_rotation_offset = 0.0
	_set_mouse_rotation_active(false)
	if is_instance_valid(barrier_preview):
		barrier_preview.queue_free()
	barrier_preview = null

func _update_preview() -> void:
	if not is_instance_valid(barrier_preview):
		var current_scene := get_tree().current_scene
		if not current_scene:
			return
		barrier_preview = WALL_SCENE.instantiate() as BarrierOrbWall
		barrier_preview.name = "SageBarrierPreview"
		barrier_preview.is_preview = true
		barrier_preview.collision_layer = 0
		barrier_preview.collision_mask = 0
		barrier_preview.modulate.a = GHOST_ALPHA
		_set_preview_visuals(barrier_preview)
		current_scene.add_child(barrier_preview)
	var aim_offset := agent.get_global_mouse_position() - agent.global_position
	if aim_offset.is_zero_approx() or not aim_offset.is_finite():
		aim_offset = Vector2.RIGHT.rotated(agent.visuals.global_rotation)
	var direction := aim_offset.normalized()
	barrier_preview.global_position = (
		agent.global_position + direction * minf(aim_offset.length(), MAX_RANGE)
	)
	if mouse_rotation_active:
		barrier_preview.global_position = rotation_anchor_position
		barrier_preview.global_rotation = rotation_anchor_angle + mouse_rotation_delta
	else:
		barrier_preview.global_rotation = direction.angle() + PI / 2.0 + preview_rotation_offset
	if mouse_rotation_active:
		_look_toward_barrier()

func _set_preview_visuals(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", true)
		elif child is LightOccluder2D:
			(child as LightOccluder2D).visible = false
		elif child is Sprite2D and child.material is CanvasItemMaterial:
			var preview_material := (child.material as CanvasItemMaterial).duplicate() as CanvasItemMaterial
			preview_material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL
			(child as Sprite2D).material = preview_material
		_set_preview_visuals(child)

func _get_mouse_facing_angle() -> float:
	var aim_offset := agent.get_global_mouse_position() - agent.global_position
	if aim_offset.is_zero_approx() or not aim_offset.is_finite():
		return agent.visuals.global_rotation
	return aim_offset.angle() + PI / 2.0

func _look_toward_barrier() -> void:
	if not agent or not agent.visuals or not is_instance_valid(barrier_preview):
		return
	var wall_direction := barrier_preview.global_position - agent.global_position
	if not wall_direction.is_zero_approx():
		agent.visuals.global_rotation = wall_direction.angle() + PI / 2.0

func _exit_tree() -> void:
	_set_mouse_rotation_active(false)

func _set_mouse_rotation_active(active: bool) -> void:
	mouse_rotation_active = active
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if rotation_start_mouse_position != Vector2.ZERO:
			get_viewport().warp_mouse(rotation_start_mouse_position)
			rotation_start_mouse_position = Vector2.ZERO

func _place_wall() -> void:
	var wall_position := barrier_preview.global_position
	var wall_rotation := barrier_preview.global_rotation
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_placement_rpc.rpc_id(1, wall_position, wall_rotation)
	else:
		if not _spawn_wall(wall_position, wall_rotation):
			return
	_return_to_current_weapon()

func _return_to_current_weapon() -> void:
	var weapon_controller = agent.weapon_controller
	if not weapon_controller or not weapon_controller.current_weapon:
		agent.set_active_ability("")
		return
	weapon_controller.suppress_shoot_until_released()
	weapon_controller.select_weapon_slot(weapon_controller.current_weapon_slot, false, true)

@rpc("any_peer", "reliable")
func request_placement_rpc(wall_position: Vector2, wall_rotation: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != agent.get_multiplayer_authority():
		return
	var wall_offset := wall_position - agent.global_position
	var rotation_offset := angle_difference(wall_offset.angle() + PI / 2.0, wall_rotation)
	var snapped_rotation := absf(absf(rotation_offset) - PI) < 0.05
	if (
		agent.is_dead
		or agent.is_match_preparing
		or agent.shop_open
		or agent.active_ability_name != ABILITY_ID
		or not wall_position.is_finite()
		or not is_finite(wall_rotation)
		or wall_offset.is_zero_approx()
		or wall_position.distance_to(agent.global_position) > MAX_RANGE + 0.5
		or (absf(rotation_offset) > 0.05 and not snapped_rotation)
		or not agent.has_ability_charge(ABILITY_ID)
	):
		return
	if not _spawn_wall(wall_position, wall_rotation):
		return
	agent.set_active_ability("")

func _spawn_wall(wall_position: Vector2, wall_rotation: float) -> bool:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	if not get_tree().current_scene or not agent.consume_ability_charge(ABILITY_ID):
		return false
	next_barrier_id += 1
	var owner_peer_id := agent.get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 1
	if multiplayer.has_multiplayer_peer():
		spawn_wall_rpc.rpc(owner_peer_id, next_barrier_id, wall_position, wall_rotation)
	else:
		_spawn_wall_instance(owner_peer_id, next_barrier_id, wall_position, wall_rotation)
	return true

@rpc("any_peer", "call_local", "reliable")
func spawn_wall_rpc(owner_peer_id: int, wall_id: int, wall_position: Vector2, wall_rotation: float) -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if (multiplayer.is_server() and sender_id != 0 and sender_id != 1) or (not multiplayer.is_server() and sender_id != 1):
			return
	if (
		owner_peer_id != agent.get_multiplayer_authority()
		or wall_id <= 0
		or not wall_position.is_finite()
		or not is_finite(wall_rotation)
	):
		return
	next_barrier_id = maxi(next_barrier_id, wall_id)
	_spawn_wall_instance(owner_peer_id, wall_id, wall_position, wall_rotation)

func _spawn_wall_instance(owner_peer_id: int, wall_id: int, wall_position: Vector2, wall_rotation: float) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return
	var wall := WALL_SCENE.instantiate() as BarrierOrbWall
	wall.name = "SageBarrier_%d_%d" % [owner_peer_id, wall_id]
	wall.add_to_group("skirmish_round_effects")
	current_scene.add_child(wall)
	wall.global_position = wall_position
	wall.global_rotation = wall_rotation
	_play_placement_animation(wall)
	AudioManager.play_world_cue(active_audio, wall_position)
	if agent.has_local_authority():
		var voice_cue := voice_audio_1 if randi_range(0, 1) == 0 else voice_audio_2
		AudioManager.play_local_cue(voice_cue, &"sage_barrier_orb_voice")

func _play_cast_audio_locally() -> void:
	AudioManager.play_local_cue(cast_audio, &"sage_barrier_orb_cast")

func _play_placement_animation(wall: StaticBody2D) -> void:
	var sprites: Array[Sprite2D] = [
		wall.get_node("Sprite2D") as Sprite2D,
		wall.get_node("Sprite2D2") as Sprite2D,
		wall.get_node("Sprite2D3") as Sprite2D,
		wall.get_node("Sprite2D4") as Sprite2D,
	]
	var collisions: Array[CollisionShape2D] = [
		wall.get_node("CollisionShape2D") as CollisionShape2D,
		wall.get_node("CollisionShape2D2") as CollisionShape2D,
		wall.get_node("CollisionShape2D3") as CollisionShape2D,
		wall.get_node("CollisionShape2D4") as CollisionShape2D,
	]
	var tween := wall.create_tween()
	for index in range(sprites.size()):
		var sprite := sprites[index]
		var target_scale_y := sprite.scale.y
		var target_position_y := sprite.position.y
		collisions[index].set_deferred("disabled", true)
		if index > 0:
			tween.tween_interval(0.07)
		tween.tween_property(sprite, "scale:y", target_scale_y, 0.16).from(0.001).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(sprite, "position:y", target_position_y, 0.16).from(target_position_y + 5.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain()
	tween.tween_callback(_enable_collisions.bind(collisions))

func _enable_collisions(collisions: Array[CollisionShape2D]) -> void:
	for shape in collisions:
		if is_instance_valid(shape):
			shape.set_deferred("disabled", false)
