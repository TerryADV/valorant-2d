class_name Lever
extends Area2D

@export var door: SlidingDoor
@export var one_time_use: bool = false
@export var ready_color: Color = Color(0.2, 1.0, 0.3, 1.0)
@export var in_use_color: Color = Color(1.0, 0.8, 0.1, 1.0)
@export var broken_color: Color = Color(1.0, 0.2, 0.2, 1.0)

@onready var lever_sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var player_inside := false
var used := false
var lever_gradient: Gradient

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prepare_gradient()

	if door:
		door.opened.connect(_on_door_opened)
		door.closed.connect(_on_door_closed)
		door.broken.connect(_on_door_broken)

	update_lever_color()

func _physics_process(_delta: float) -> void:
	# Mantiene la detección aunque body_entered no se emita al instanciar la escena.
	player_inside = false
	for body in get_overlapping_bodies():
		if is_player(body):
			player_inside = true
			break

	if Input.is_action_just_pressed("interact"):
		toggle_door()

func toggle_door() -> void:
	var target_door := door
	if not target_door:
		target_door = get_parent() as SlidingDoor

	if not target_door or (one_time_use and used):
		return

	if target_door.is_open:
		target_door.close_door()
	else:
		target_door.open_door()

	used = true

func _on_door_opened() -> void:
	set_lever_color(in_use_color)

func _on_door_closed() -> void:
	set_lever_color(ready_color)

func _on_door_broken() -> void:
	set_lever_color(broken_color)

func update_lever_color() -> void:
	var target_door := door
	if not target_door:
		target_door = get_parent() as SlidingDoor

	if not target_door:
		return

	if target_door.is_broken:
		set_lever_color(broken_color)
	elif target_door.is_open:
		set_lever_color(in_use_color)
	else:
		set_lever_color(ready_color)

func set_lever_color(color: Color) -> void:
	if lever_gradient:
		for point in lever_gradient.get_point_count():
			lever_gradient.set_color(point, color)
	elif lever_sprite:
		lever_sprite.modulate = color

func _prepare_gradient() -> void:
	if not lever_sprite:
		return

	var gradient_texture := lever_sprite.texture as GradientTexture1D
	if not gradient_texture or not gradient_texture.gradient:
		return

	# Cada palanca tiene su propio gradiente para no modificar otros sprites.
	gradient_texture = gradient_texture.duplicate() as GradientTexture1D
	gradient_texture.gradient = gradient_texture.gradient.duplicate() as Gradient
	lever_sprite.texture = gradient_texture
	lever_gradient = gradient_texture.gradient

func _on_body_entered(body: Node2D) -> void:
	if is_player(body):
		player_inside = true

func _on_body_exited(body: Node2D) -> void:
	if is_player(body):
		player_inside = false

func is_player(body: Node2D) -> bool:
	return body.is_in_group("player") or body.name == "BaseAgent"
