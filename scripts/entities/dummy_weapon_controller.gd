extends RefCounted

enum WeaponSound { EQUIP, SHOT, RELOAD, MELEE }

var _dummy: Node
var _available_weapons: Array[WeaponData] = []

func setup(dummy: Node, available_weapons: Array[WeaponData]) -> void:
	_dummy = dummy
	_available_weapons = available_weapons

func apply_weapon(weapon: WeaponData) -> void:
	var weapon_changed: bool = _dummy.get("current_weapon") != weapon
	_dummy.set("current_weapon", weapon)
	_dummy.set("ammo_in_magazine", weapon.magazine_size if not weapon.is_melee else 0)
	var weapon_sprite := _dummy.get("weapon_sprite") as Sprite2D
	weapon_sprite.texture = weapon.weapon_sprite
	weapon_sprite.visible = weapon.weapon_sprite != null
	if weapon_changed and _dummy.get_multiplayer().has_multiplayer_peer():
		play_weapon_cue(WeaponSound.EQUIP, (_dummy as Node2D).global_position)

func sync_weapon_selection(weapon_index: int) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if weapon_index < 0 or weapon_index >= _available_weapons.size():
		push_warning("Rejected a dummy weapon selection with an invalid index.")
		return
	apply_weapon(_available_weapons[weapon_index])

func spawn_bullet(
	weapon: WeaponData,
	start_position: Vector2,
	direction: Vector2,
	visual_only: bool,
	play_shot_sound: bool
) -> void:
	if play_shot_sound:
		play_weapon_cue(WeaponSound.SHOT, start_position)
	var bullet_scene: PackedScene = preload("res://scenes/weapons/bullet.tscn")
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.init_bullet(
		start_position,
		direction,
		_dummy as Node2D,
		weapon.wall_penetration,
		weapon.weapon_name,
		weapon.short_range,
		weapon.medium_range,
		weapon.short_damage,
		weapon.medium_damage,
		weapon.long_damage
	)
	bullet.set_tracer_enabled(true)
	bullet.network_visual_only = visual_only
	_dummy.get_parent().add_child(bullet)

func sync_bullet(
	weapon_index: int,
	start_position: Vector2,
	direction: Vector2,
	play_shot_sound: bool
) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if weapon_index < 0 or weapon_index >= _available_weapons.size():
		push_warning("Rejected a dummy shot with an invalid weapon index.")
		return
	if not start_position.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		push_warning("Rejected a dummy shot with an invalid position or direction.")
		return
	var weapon := _available_weapons[weapon_index]
	if _dummy.get("current_weapon") != weapon:
		apply_weapon(weapon)
	var multiplayer_api := _dummy.get_multiplayer()
	spawn_bullet(
		weapon,
		start_position,
		direction,
		multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server(),
		play_shot_sound
	)

func play_weapon_cue(sound: int, world_position: Vector2) -> void:
	var weapon := _dummy.get("current_weapon") as WeaponData
	if not weapon:
		return
	var cue := _get_weapon_cue(weapon, sound)
	if not cue:
		return
	var multiplayer_api := _dummy.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		return
	AudioManager.play_world_cue(cue, world_position)
	if multiplayer_api.has_multiplayer_peer():
		_dummy.rpc("sync_dummy_weapon_sound", sound, _available_weapons.find(weapon), world_position)

func play_reload_sound() -> void:
	play_weapon_cue(WeaponSound.RELOAD, (_dummy as Node2D).global_position)

func sync_weapon_sound(sound: int, weapon_index: int, world_position: Vector2) -> void:
	if not bool((_dummy.get("_dummy_controller") as RefCounted).is_server_rpc_sender()):
		return
	if sound < WeaponSound.EQUIP or sound > WeaponSound.MELEE:
		push_warning("Rejected dummy weapon audio with an invalid sound type.")
		return
	if weapon_index < 0 or weapon_index >= _available_weapons.size():
		push_warning("Rejected dummy weapon audio with an invalid weapon index.")
		return
	var cue := _get_weapon_cue(_available_weapons[weapon_index], sound)
	if not cue:
		push_warning("Rejected dummy weapon audio for an invalid audio resource.")
		return
	AudioManager.play_world_cue(cue, world_position)

func _get_weapon_cue(weapon: WeaponData, sound: int) -> AudioCue:
	match sound:
		WeaponSound.EQUIP:
			return weapon.equip_audio
		WeaponSound.SHOT:
			return weapon.shot_audio
		WeaponSound.RELOAD:
			return weapon.reload_audio
		WeaponSound.MELEE:
			return weapon.melee_light_audio
	return null
