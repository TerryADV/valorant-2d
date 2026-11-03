class_name SlidingDoor
extends AnimatableBody2D

signal damaged(amount: float, remaining_health: float)
signal broken
signal opened
signal closed

@export_group("Durability")
@export var max_health: float = 100.0
@export var destroy_on_zero: bool = false

@export_group("Sliding")
@export_enum("Horizontal", "Vertical") var stretch_axis: int = 0
@export var slide_duration: float = 1.0
@export var starts_open: bool = false
@export var push_speed: float = 90.0

@export_group("Damage Tint")
@export var tint_on_damage: bool = true
@export var damage_color: Color = Color(1.0, 0.35, 0.2, 1.0)

@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

var current_health: float
var closed_scale: Vector2
var open_scale: Vector2
var is_open := false
var is_broken := false
var is_closing := false
var movement_tween: Tween

func _ready() -> void:
	current_health = max_health
	open_scale = scale
	closed_scale = Vector2(0.0, open_scale.y) if stretch_axis == 0 else Vector2(open_scale.x, 0.0)

	if starts_open:
		is_open = true
		scale = open_scale
		set_collision_enabled(true)
	else:
		scale = closed_scale
		set_collision_enabled(false)

func _physics_process(delta: float) -> void:
	if is_closing:
		push_overlapping_players(delta)

func take_damage(amount: float, _attacker: Node = null, _weapon_name: String = "") -> void:
	if is_broken or amount <= 0.0:
		return

	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, current_health)

	if tint_on_damage:
		update_damage_tint()

	if current_health <= 0.0:
		break_door()

func open_door() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_door_state.rpc_id(1, true)
		return
	if multiplayer.has_multiplayer_peer():
		sync_door_state.rpc(true)
		return
	_apply_open_door()

func _apply_open_door() -> void:
	if is_broken or is_open:
		return

	is_open = true
	is_closing = false
	set_collision_enabled(true)
	move_door(open_scale, func(): opened.emit())

func close_door() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_door_state.rpc_id(1, false)
		return
	if multiplayer.has_multiplayer_peer():
		sync_door_state.rpc(false)
		return
	_apply_close_door()

func _apply_close_door() -> void:
	if is_broken or not is_open:
		return

	# No cierres la puerta sobre un jugador que todavía está dentro.
	if is_occupied():
		return

	is_open = false
	is_closing = true
	set_collision_enabled(false)
	move_door(closed_scale, func(): closed.emit())

@rpc("any_peer", "reliable")
func request_door_state(should_open: bool) -> void:
	if not multiplayer.is_server():
		return
	sync_door_state.rpc(should_open)

@rpc("authority", "call_local", "reliable")
func sync_door_state(should_open: bool) -> void:
	if should_open:
		_apply_open_door()
	else:
		_apply_close_door()

func is_occupied() -> bool:
	if not collision_shape or not collision_shape.shape:
		return false

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 16
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var body: Node2D = result.get("collider") as Node2D
		if body is CharacterBody2D:
			return true

	return false

func move_door(target_scale: Vector2, on_finished: Callable = Callable()) -> void:
	if movement_tween:
		movement_tween.kill()

	movement_tween = create_tween()
	movement_tween.set_trans(Tween.TRANS_QUAD)
	movement_tween.set_ease(Tween.EASE_IN_OUT)
	movement_tween.tween_property(self, "scale", target_scale, slide_duration)
	movement_tween.tween_callback(func():
		is_closing = false
		if on_finished.is_valid():
			on_finished.call()
	)

func push_overlapping_players(delta: float) -> void:
	if not collision_shape or not collision_shape.shape:
		return

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = 16
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	var axis := global_transform.x.normalized() if stretch_axis == 0 else global_transform.y.normalized()
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var body = result.get("collider")
		if not body is CharacterBody2D:
			continue

		var side: float = sign((body.global_position - global_position).dot(axis))
		if is_zero_approx(side):
			side = 1.0

		body.global_position += axis * side * push_speed * delta

func break_door() -> void:
	if is_broken:
		return

	if multiplayer.has_multiplayer_peer():
		if not multiplayer.is_server():
			return
		sync_door_broken.rpc()
		return

	_apply_broken_state()

@rpc("authority", "call_local", "reliable")
func sync_door_broken() -> void:
	_apply_broken_state()

func _apply_broken_state() -> void:
	if is_broken:
		return

	is_broken = true
	current_health = 0.0
	is_closing = false
	if movement_tween:
		movement_tween.kill()
	broken.emit()
	set_collision_enabled(false)

	if destroy_on_zero:
		queue_free()
	else:
		visible = false

func set_collision_enabled(enabled: bool) -> void:
	if collision_shape:
		collision_shape.set_deferred("disabled", not enabled)

func update_damage_tint() -> void:
	var damage_ratio := 1.0 - (current_health / max_health)
	var drawable := get_node_or_null("Sprite2D") as CanvasItem
	if drawable:
		drawable.modulate = Color.WHITE.lerp(damage_color, damage_ratio)
