extends RefCounted

const MIN_EQUIP_SCALE := 0.05

var _controller: Node

func setup(controller: Node) -> void:
	_controller = controller

func animate_melee_attack(heavy_attack: bool) -> void:
	var weapon_pivot := _controller.get("weapon_pivot") as Node2D
	if not weapon_pivot:
		return
	stop_melee_attack_animation()
	var base_rotation := float(_controller.get("weapon_pivot_base_rotation"))
	weapon_pivot.rotation = base_rotation
	var swing_angle := deg_to_rad(65.0 if heavy_attack else 45.0)
	var swing_duration := 0.24 if heavy_attack else 0.12
	var tween := weapon_pivot.create_tween()
	tween.tween_property(
		weapon_pivot, "rotation", base_rotation + swing_angle, swing_duration * 0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		weapon_pivot, "rotation", base_rotation, swing_duration * 0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_controller.set("melee_attack_tween", tween)

func stop_melee_attack_animation() -> void:
	var tween := _controller.get("melee_attack_tween") as Tween
	if tween and tween.is_running():
		tween.kill()
	_controller.set("melee_attack_tween", null)
	var weapon_pivot := _controller.get("weapon_pivot") as Node2D
	if weapon_pivot:
		weapon_pivot.rotation = float(_controller.get("weapon_pivot_base_rotation"))

func start_reload_animation(duration: float) -> void:
	var weapon_sprite := _controller.get("weapon_sprite") as Sprite2D
	if not weapon_sprite:
		return
	stop_reload_animation()
	var tween := weapon_sprite.create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(
		weapon_sprite,
		"rotation",
		float(_controller.get("weapon_sprite_base_rotation")) - TAU,
		maxf(duration, 0.01)
	)
	_controller.set("reload_tween", tween)

func stop_reload_animation() -> void:
	var tween := _controller.get("reload_tween") as Tween
	if tween and tween.is_running():
		tween.kill()
	_controller.set("reload_tween", null)
	var weapon_sprite := _controller.get("weapon_sprite") as Sprite2D
	if weapon_sprite:
		weapon_sprite.rotation = float(_controller.get("weapon_sprite_base_rotation"))

func update_visual(animate_equip: bool = false) -> void:
	var weapon_sprite := _controller.get("weapon_sprite") as Sprite2D
	if not weapon_sprite:
		return
	stop_reload_animation()
	var equip_tween := _controller.get("equip_tween") as Tween
	if bool(_controller.get("weapon_hidden_by_ability")):
		if equip_tween:
			equip_tween.kill()
		_controller.set("is_equipping", false)
		weapon_sprite.visible = false
		return
	var agent := _controller.get("agent") as BaseAgent
	if agent and not agent.active_ability_name.is_empty():
		if equip_tween:
			equip_tween.kill()
		_controller.set("is_equipping", false)
		weapon_sprite.visible = false
		return
	var current_weapon := _controller.get("current_weapon") as WeaponData
	if agent and agent.is_ai_dummy:
		current_weapon = agent.current_weapon
	if not current_weapon or not current_weapon.weapon_sprite:
		if equip_tween:
			equip_tween.kill()
		_controller.set("is_equipping", false)
		weapon_sprite.texture = null
		weapon_sprite.visible = false
		return

	weapon_sprite.texture = current_weapon.weapon_sprite
	weapon_sprite.visible = true
	var base_scale: Vector2 = _controller.get("weapon_sprite_base_scale")
	if not animate_equip:
		if equip_tween:
			equip_tween.kill()
		_controller.set("is_equipping", false)
		weapon_sprite.scale = base_scale
		return

	if equip_tween:
		equip_tween.kill()
	_controller.set("is_equipping", true)
	weapon_sprite.scale = base_scale * MIN_EQUIP_SCALE
	var duration := maxf(current_weapon.equip_time, 0.01)
	equip_tween = weapon_sprite.create_tween()
	equip_tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	equip_tween.tween_property(weapon_sprite, "scale", base_scale, duration)
	equip_tween.tween_callback(_finish_equip_animation)
	_controller.set("equip_tween", equip_tween)

func set_weapon_hidden_by_ability(hidden: bool) -> void:
	_controller.set("weapon_hidden_by_ability", hidden)
	update_visual(not hidden)

func _finish_equip_animation() -> void:
	_controller.set("is_equipping", false)
