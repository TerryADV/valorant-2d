class_name DroppedWeapon
extends Area2D

@export var weapon_data: WeaponData

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var can_be_picked: bool = true
var ammo_in_magazine: int = 0
var reserve_ammo: int = 0
var ammo_initialized := false
var network_spawned := false

func _ready() -> void:
	add_to_group("dropped_weapons")
	body_entered.connect(_on_body_entered)
	if not weapon_data:
		weapon_data = preload("res://resources/weapons/vandal.tres")
	if not ammo_initialized:
		ammo_in_magazine = weapon_data.magazine_size
		reserve_ammo = weapon_data.reserve_ammo
		ammo_initialized = true
	update_visuals()

func _on_body_entered(body: Node2D) -> void:
	if not can_be_picked or not body is BaseAgent:
		return
	if not body.has_local_authority():
		return

	var controller = body.get_node_or_null("Components/WeaponController")
	if not controller or not controller.has_method("try_auto_pickup_weapon"):
		return
	controller.try_auto_pickup_weapon(self)

func init_weapon(p_data: WeaponData, start_pos: Vector2, throw_dir: Vector2 = Vector2.ZERO, p_ammo_in_magazine: int = -1, p_reserve_ammo: int = -1) -> void:
	weapon_data = p_data
	ammo_in_magazine = weapon_data.magazine_size if p_ammo_in_magazine < 0 else p_ammo_in_magazine
	reserve_ammo = weapon_data.reserve_ammo if p_reserve_ammo < 0 else p_reserve_ammo
	ammo_initialized = true
	global_position = start_pos
	update_visuals()

	# Si se arroja, hace la animación física de vuelo suave con rotación
	if throw_dir != Vector2.ZERO:
		animate_throw(start_pos, throw_dir)

func update_visuals() -> void:
	if not sprite:
		return

	if not weapon_data:
		return

	var tex: Texture2D = weapon_data.weapon_sprite
	if not tex:
		tex = preload("res://assets/sprites/weapons/vandal.png")

	sprite.texture = tex

func animate_throw(from_pos: Vector2, dir: Vector2) -> void:
	can_be_picked = false
	var throw_distance: float = 10.0 # Distancia a la que sale volando
	var target_pos: Vector2 = from_pos + (dir.normalized() * throw_distance)

	# Raycast para que si hay una pared enfrente no la atraviese al arrojar
	if is_inside_tree() and get_world_2d():
		var space_state := get_world_2d().direct_space_state
		if space_state:
			var query := PhysicsRayQueryParameters2D.create(from_pos, target_pos)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit := space_state.intersect_ray(query)
			if hit:
				target_pos = hit.position - (dir.normalized() * 6.0)

	var tween := create_tween().set_parallel(true)
	# Movimiento suave con desaceleración física (Ease Out Quad)
	tween.tween_property(self, "global_position", target_pos, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Giro suave mientras vuela
	var random_spin := randf_range(-PI * 0.8, PI * 0.8)
	tween.tween_property(self, "rotation", rotation + random_spin, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Se vuelve recogible al terminar de caer
	tween.chain().tween_callback(func(): can_be_picked = true)
