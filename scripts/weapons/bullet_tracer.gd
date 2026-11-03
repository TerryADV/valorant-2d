class_name BulletTracer
extends Line2D

func init_tracer(from_pos: Vector2, to_pos: Vector2, color: Color = Color(1.0, 0.9, 0.4, 0.9)) -> void:
	top_level = true
	z_index = 10
	width = 1.0 # Muy delgada y nítida

	# En lugar de una línea que cruza todo el mapa de golpe,
	# dibujamos una bala corta (estilo segmento/proyectil) que viaja hacia el impacto
	var dir := (to_pos - from_pos).normalized()
	var total_dist := from_pos.distance_to(to_pos)
	var bullet_length := minf(14.0, total_dist) # Solo 14px de largo

	var start_segment := to_pos - (dir * bullet_length)
	
	default_color = color
	clear_points()
	add_point(start_segment)
	add_point(to_pos)

	# Se desvanece de inmediato (0.04s)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.04)
	tween.tween_callback(queue_free)
