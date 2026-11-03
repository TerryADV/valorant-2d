extends RefCounted

const LOW_STATUS_TEXTURE: Texture2D = preload("res://assets/sprites/ui/main/decor2_low.png")
const LOW_STATUS_RATIO := 0.33

var _health_decor: TextureRect
var _bullet_decor: TextureRect
var _health_default_texture: Texture2D
var _bullet_default_texture: Texture2D

func setup(health_decor: TextureRect, bullet_decor: TextureRect) -> void:
	_health_decor = health_decor
	_bullet_decor = bullet_decor
	_health_default_texture = health_decor.texture if health_decor else null
	_bullet_default_texture = bullet_decor.texture if bullet_decor else null

func update_health(current_health: float, max_health: float) -> void:
	var ratio := current_health / max_health if max_health > 0.0 else 0.0
	if _health_decor:
		_health_decor.texture = LOW_STATUS_TEXTURE if ratio < LOW_STATUS_RATIO else _health_default_texture

func update_ammo(current_ammo: int, magazine_capacity: int) -> void:
	var ratio := float(current_ammo) / float(magazine_capacity) if magazine_capacity > 0 else 1.0
	if _bullet_decor:
		_bullet_decor.texture = LOW_STATUS_TEXTURE if ratio < LOW_STATUS_RATIO else _bullet_default_texture
