class_name BreakableObject
extends StaticBody2D

signal damaged(amount: float, remaining_health: float)
signal broken

@export_group("Durability")
@export var max_health: float = 100.0
@export var destroy_on_zero: bool = true
@export var destroy_delay: float = 0.0

@export_group("Feedback")
@export var tint_on_damage: bool = true
@export var damage_color: Color = Color(1.0, 0.35, 0.2, 1.0)

@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var collision_polygon: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D")

var current_health: float
var is_broken: bool = false

func _ready() -> void:
	current_health = max_health

func take_damage(amount: float, _attacker: Node = null, _weapon_name: String = "") -> void:
	if is_broken or amount <= 0.0:
		return

	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, current_health)

	if tint_on_damage:
		update_damage_tint()

	if current_health <= 0.0:
		break_object()

func break_object() -> void:
	if is_broken:
		return

	is_broken = true
	broken.emit()

	set_collision_enabled(false)

	if destroy_on_zero:
		if destroy_delay > 0.0:
			await get_tree().create_timer(destroy_delay).timeout
		queue_free()
	else:
		visible = false

func set_collision_enabled(enabled: bool) -> void:
	if collision_shape:
		collision_shape.set_deferred("disabled", not enabled)
	if collision_polygon:
		collision_polygon.set_deferred("disabled", not enabled)

func update_damage_tint() -> void:
	var drawable := find_drawable_child()
	if not drawable:
		return

	var damage_ratio := 1.0 - (current_health / max_health)
	drawable.modulate = Color.WHITE.lerp(damage_color, damage_ratio)

func find_drawable_child() -> CanvasItem:
	for child in get_children():
		if child is Sprite2D or child is Polygon2D:
			return child as CanvasItem
	return null
