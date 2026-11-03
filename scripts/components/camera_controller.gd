class_name AgentCameraController
extends Node

@export var look_ahead_distance: float = 0
@export_range(0.0, 1.0, 0.01) var edge_margin_ratio: float = 0.3

@onready var camera: Camera2D = get_parent().get_parent().get_node_or_null("Camera2D") as Camera2D
@onready var agent = get_parent().get_parent()
var base_zoom := Vector2.ONE
var applied_zoom := Vector2.ZERO

func _ready() -> void:
	if camera:
		base_zoom = camera.zoom

func process_camera_look_ahead() -> void:
	if not camera or agent.shop_open:
		return

	var is_aiming: bool = agent and agent.weapon_controller.is_aiming()
	var weapon_zoom: float = 1.0
	if is_aiming and agent.weapon_controller.current_weapon:
		weapon_zoom = agent.weapon_controller.get_current_aim_zoom()
	var target_zoom: Vector2 = base_zoom / (weapon_zoom if is_aiming else 1.0)
	if target_zoom != applied_zoom:
		camera.zoom = target_zoom
		applied_zoom = target_zoom

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var norm: Vector2 = Vector2(mouse_pos.x / viewport_size.x, mouse_pos.y / viewport_size.y)
	var push_dir := Vector2.ZERO
	if norm.x < edge_margin_ratio:
		push_dir.x = -(edge_margin_ratio - norm.x) / edge_margin_ratio
	elif norm.x > 1.0 - edge_margin_ratio:
		push_dir.x = (norm.x - (1.0 - edge_margin_ratio)) / edge_margin_ratio
	if norm.y < edge_margin_ratio:
		push_dir.y = -(edge_margin_ratio - norm.y) / edge_margin_ratio
	elif norm.y > 1.0 - edge_margin_ratio:
		push_dir.y = (norm.y - (1.0 - edge_margin_ratio)) / edge_margin_ratio
	var zoom: Vector2 = camera.zoom
	var look_ahead_world: Vector2 = Vector2(
		look_ahead_distance / maxf(zoom.x, 0.001),
		look_ahead_distance / maxf(zoom.y, 0.001)
	)
	camera.position = push_dir * look_ahead_world
