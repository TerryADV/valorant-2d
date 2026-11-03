class_name BulletImpact
extends Node2D

@export var radius: float = 0.8
@export var lifetime: float = 10.0
@export var impact_color: Color = Color(0.04, 0.04, 0.04, 1.0)

func _ready() -> void:
	z_index = 20
	var light_material := CanvasItemMaterial.new()
	light_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY
	material = light_material
	light_mask = 1
	queue_redraw()
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, impact_color)
