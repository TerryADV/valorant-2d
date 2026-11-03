extends RefCounted

var _actor: Node2D
var _team_context: Object
var _original_materials: Dictionary = {}
var _is_showing_unshaded := false

func setup(actor: Node2D, team_context: Object = null) -> void:
	_actor = actor
	_team_context = team_context

func set_team_context(team_context: Object) -> void:
	_team_context = team_context
	process(0.0)

func process(_delta: float) -> void:
	if not is_instance_valid(_actor):
		return
	var should_show_unshaded := _should_show_unshaded()
	if should_show_unshaded:
		if not _is_showing_unshaded:
			_is_showing_unshaded = true
			_set_team_visibility(_actor)
	elif _is_showing_unshaded:
		_is_showing_unshaded = false
		_restore_materials()

func _should_show_unshaded() -> bool:
	if not _team_context or not _team_context.has_method("is_actor_ally"):
		return false
	if bool(_actor.get("is_ai_dummy")) and not bool(_actor.get("is_in_match")):
		return false
	return bool(_team_context.call("is_actor_ally", _actor))

func _set_team_visibility(node: Node) -> void:
	var canvas_item := node as CanvasItem
	if canvas_item and canvas_item.material is CanvasItemMaterial:
		var source_material := canvas_item.material as CanvasItemMaterial
		if source_material.light_mode != CanvasItemMaterial.LIGHT_MODE_UNSHADED:
			if not _original_materials.has(canvas_item):
				_original_materials[canvas_item] = source_material
			var ally_material := source_material.duplicate() as CanvasItemMaterial
			ally_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
			canvas_item.material = ally_material
	for child in node.get_children():
		_set_team_visibility(child)

func _restore_materials() -> void:
	for item in _original_materials:
		if is_instance_valid(item):
			(item as CanvasItem).material = _original_materials[item]
	_original_materials.clear()
