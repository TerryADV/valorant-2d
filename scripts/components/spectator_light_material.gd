extends RefCounted

static func set_dummy_lights_visible(actor: Node, visible_state: bool) -> void:
	if not is_instance_valid(actor):
		return
	var lights := actor.get_node_or_null("Visuals/Lights") as CanvasItem
	if not lights:
		return
	if visible_state:
		if not lights.has_meta("spectator_previous_visible"):
			lights.set_meta("spectator_previous_visible", lights.visible)
		lights.visible = true
	else:
		if lights.has_meta("spectator_previous_visible"):
			lights.visible = bool(lights.get_meta("spectator_previous_visible"))
			lights.remove_meta("spectator_previous_visible")
