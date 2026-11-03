class_name AgentCircleVisual
extends Node2D

var circle_color: Color = Color(0.0, 1.0, 1.0, 1.0)

func set_agent_color(color: Color) -> void:
	circle_color = color
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, circle_color)
