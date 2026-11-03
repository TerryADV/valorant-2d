class_name Bullet
extends Area2D

@export var speed: float = 1400.0 # Velocidad rápida de bala
@export var max_range: float = 1800.0

var direction: Vector2 = Vector2.ZERO
var short_range: float = 15.0
var medium_range: float = 30.0
var short_damage: float = 40.0
var medium_damage: float = 34.0
var long_damage: float = 27.0
var shooter: Node2D = null
var weapon_name: String = ""
var penetration_power: float = 0.0
var network_visual_only: bool = false
var tracer_enabled: bool = false
var blocked_at_spawn: bool = false
var shooter_overlap_exclusions: Array[RID] = []

@onready var bullet_sprite: Sprite2D = $Sprite2D

# Daño que conserva la bala después de atravesar cada nivel de muro.
# None no llega a este punto porque detiene la bala.
const WALL_DAMAGE_MULTIPLIER := {
	Wall.PenetrationLevel.LOW: 0.75,
	Wall.PenetrationLevel.MEDIUM: 0.50,
	Wall.PenetrationLevel.HIGH: 0.25,
}
const BULLET_PENETRABLE_GROUP := "bullet_penetrable"
const PLATFORM_LAYER_MASK := 1 << 2
const DECORATION_LAYER_MASK := 1 << 1
const BULLET_IGNORED_LAYER_MASK := 1 << 1

var distance_travelled: float = 0.0

func _ready() -> void:
	top_level = true
	update_tracer_visibility()

func init_bullet(
	start_pos: Vector2,
	target_dir: Vector2,
	p_shooter: Node2D = null,
	p_wall_penetration: String = "Medium",
	p_weapon_name: String = "",
	p_short_range: float = 15.0,
	p_medium_range: float = 30.0,
	p_short_damage: float = 40.0,
	p_medium_damage: float = 34.0,
	p_long_damage: float = 27.0
) -> void:
	global_position = start_pos
	direction = target_dir.normalized()
	# Como el sprite de la bala es vertical apuntando arriba/abajo (-Y), sumamos PI / 2 para alinear con direction
	rotation = direction.angle() + (PI / 2.0)
	short_range = maxf(p_short_range, 0.0)
	medium_range = maxf(p_medium_range, short_range)
	short_damage = p_short_damage
	medium_damage = p_medium_damage
	long_damage = p_long_damage
	shooter = p_shooter
	weapon_name = p_weapon_name
	penetration_power = get_penetration_power(p_wall_penetration)
	_collect_shooter_overlap_collisions()
	update_tracer_visibility()

func _collect_shooter_overlap_collisions() -> void:
	if not shooter or not shooter.is_inside_tree():
		return
	var shooter_shape := shooter.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not shooter_shape or not shooter_shape.shape:
		return

	var excluded: Array[RID] = []
	add_collision_rids(shooter, excluded)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shooter_shape.shape
	query.transform = shooter_shape.global_transform
	query.collision_mask = 1 | 2 | 4 | 8 | 16 | 32
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = excluded

	for result in shooter.get_world_2d().direct_space_state.intersect_shape(query):
		var collider: Object = result.get("collider")
		if not (collider is Wall or _is_bullet_penetrable_collider(collider)):
			continue
		var wall_level: int = (
			(collider as Wall).get_penetration_level()
			if collider is Wall
			else Wall.PenetrationLevel.MEDIUM
		)
		if wall_level == Wall.PenetrationLevel.NONE:
			if _is_shooter_overlapping_traversable_body(collider):
				if collider is CollisionObject2D:
					shooter_overlap_exclusions.append((collider as CollisionObject2D).get_rid())
				continue
			blocked_at_spawn = true
			return
		if collider is CollisionObject2D:
			shooter_overlap_exclusions.append((collider as CollisionObject2D).get_rid())

func set_tracer_enabled(enabled: bool) -> void:
	tracer_enabled = enabled
	update_tracer_visibility()

func update_tracer_visibility() -> void:
	if bullet_sprite:
		bullet_sprite.visible = tracer_enabled

func get_penetration_power(level: String) -> float:
	match level.to_lower():
		"none":
			return 0.0
		"low":
			return 1.0
		"high":
			return 3.0
		_:
			return 2.0

func _physics_process(delta: float) -> void:
	if blocked_at_spawn:
		queue_free()
		return
	var move_vec := direction * (speed * delta)
	var from_pos := global_position
	var to_pos := from_pos + move_vec
	var remaining_from := from_pos
	var remaining_to := to_pos
	var frame_distance_travelled: float = 0.0
	var excluded: Array[RID] = [get_rid()]
	excluded.append_array(shooter_overlap_exclusions)
	if shooter:
		add_collision_rids(shooter, excluded)

	# Puede encontrar varios impactos en el mismo frame: muro y objetivo detrás.
	for _i in range(8):
		if remaining_from.distance_to(remaining_to) <= 0.01:
			break

		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(remaining_from, remaining_to)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.collision_mask = 1 | 4 | 8 | 16 | 32
		query.exclude = excluded

		var hit := space_state.intersect_ray(query)
		if not hit:
			break

		global_position = hit.position
		frame_distance_travelled += remaining_from.distance_to(hit.position)
		var collider: Object = hit.collider
		if not collider is Wall and _is_platform_collider(collider):
			if collider is CollisionObject2D:
				excluded.append((collider as CollisionObject2D).get_rid())
			remaining_from = hit.position + direction * 0.5
			continue
		if collider is BreakableObject:
			handle_hit(
				collider,
				distance_travelled + frame_distance_travelled,
				int(hit.get("shape", -1))
			)
			queue_free()
			return

		if (
			collider is Node
			and not collider is Wall
			and (collider as Node).is_in_group("updraft_traversable")
			and not (collider as Node).has_method("take_damage")
		):
			var updraft_target_hit := _get_updraft_agent_hit_through_body(
				collider, remaining_from, remaining_to, excluded
			)
			if not updraft_target_hit.is_empty():
				global_position = updraft_target_hit.position
				handle_hit(
					updraft_target_hit.collider,
					distance_travelled
					+ frame_distance_travelled
					+ hit.position.distance_to(updraft_target_hit.position),
					int(updraft_target_hit.get("shape", -1))
				)
				queue_free()
				return
			if _is_shooter_overlapping_traversable_body(collider):
				if collider is CollisionObject2D:
					excluded.append((collider as CollisionObject2D).get_rid())
				remaining_from = hit.position + direction * 0.5
				continue
			queue_free()
			return
		if _should_bullet_ignore_collider(collider):
			if collider is CollisionObject2D:
				excluded.append((collider as CollisionObject2D).get_rid())
			remaining_from = hit.position + direction * 0.5
			continue

		if shooter and collider is Node and DamageSystem.is_same_actor(collider, shooter):
			if collider is CollisionObject2D:
				excluded.append(collider.get_rid())
			remaining_from = hit.position + direction * 0.5
			continue

		if collider is Wall or _is_bullet_penetrable_collider(collider):
			var wall_level: int = (
				collider.get_penetration_level()
				if collider is Wall
				else Wall.PenetrationLevel.MEDIUM
			)
			if wall_level != Wall.PenetrationLevel.NONE:
				spawn_impact(hit.position)

			var wall_cost := get_wall_cost(wall_level)
			if penetration_power < wall_cost:
				queue_free()
				return

			penetration_power -= wall_cost
			var damage_multiplier: float = WALL_DAMAGE_MULTIPLIER.get(wall_level, 0.0)
			short_damage *= damage_multiplier
			medium_damage *= damage_multiplier
			long_damage *= damage_multiplier
			excluded.append(collider.get_rid())
			remaining_from = hit.position + direction * 0.5
			continue

		handle_hit(
			collider, distance_travelled + frame_distance_travelled, int(hit.get("shape", -1))
		)
		queue_free()
		return

	global_position = to_pos

	frame_distance_travelled += remaining_from.distance_to(remaining_to)
	distance_travelled += frame_distance_travelled
	if distance_travelled >= max_range:
		queue_free()

func _is_bullet_penetrable_collider(collider: Object) -> bool:
	return collider is Node and (collider as Node).is_in_group(BULLET_PENETRABLE_GROUP)

func _get_updraft_agent_hit_through_body(
	body: Object,
	from_position: Vector2,
	to_position: Vector2,
	excluded: Array[RID]
) -> Dictionary:
	if not body is PhysicsBody2D:
		return {}
	# The target can be deeper inside a thick wall than the bullet travels in a
	# single physics frame. Extend the verification ray to the remaining range.
	var ray_length := maxf(
		to_position.distance_to(from_position),
		maxf(max_range - distance_travelled, 0.0)
	)
	var ray_end := from_position + direction * ray_length
	var candidates: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := DamageSystem.resolve_target(node) as BaseAgent
		if not candidate:
			continue
		if shooter and DamageSystem.is_same_actor(candidate, shooter):
			continue
		if shooter is BaseAgent and shooter.is_ai_dummy and shooter.target_actor != candidate:
			continue
		if not _is_agent_overlapping_traversable_body(candidate, body):
			continue
		var candidate_hit := _get_agent_ray_hit(
			candidate, from_position, ray_end, excluded
		)
		if candidate_hit.is_empty():
			continue
		candidates.append(candidate_hit)

	# Some agents are not assigned to a "player" group (for example local test
	# agents), so include all BaseAgent nodes from the active scene as a fallback.
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "BaseAgent", true, false):
			var candidate := node as BaseAgent
			if not candidate or _contains_hit_for_target(candidates, candidate):
				continue
			if shooter and DamageSystem.is_same_actor(candidate, shooter):
				continue
			if (
				shooter is BaseAgent
				and shooter.is_ai_dummy
				and shooter.target_actor != candidate
			):
				continue
			if not _is_agent_overlapping_traversable_body(candidate, body):
				continue
			var candidate_hit := _get_agent_ray_hit(
				candidate, from_position, ray_end, excluded
			)
			if not candidate_hit.is_empty():
				candidates.append(candidate_hit)

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return from_position.distance_squared_to(a.position) < from_position.distance_squared_to(b.position)
	)
	return candidates[0]

func _get_agent_ray_hit(
	target: BaseAgent,
	from_position: Vector2,
	to_position: Vector2,
	excluded: Array[RID]
) -> Dictionary:
	var collision_shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not collision_shape or not collision_shape.shape:
		return {}
	var target_excluded: Array[RID] = []
	target_excluded.append_array(excluded)
	if shooter:
		add_collision_rids(shooter, target_excluded)
	# The first ray has already confirmed that the bullet hit the traversable
	# body occupied by this target. This second ray checks whether its trajectory
	# intersects the target's hitbox, ignoring other bodies that share the same
	# collision layer (such as the traversable wall itself).
	var scene := get_tree().current_scene
	if scene:
		for node in scene.find_children("*", "CollisionObject2D", true, false):
			var collision_object := node as CollisionObject2D
			if collision_object and collision_object != target:
				target_excluded.append(collision_object.get_rid())
	var query := PhysicsRayQueryParameters2D.create(from_position, to_position)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = target.collision_layer
	query.exclude = target_excluded
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or DamageSystem.resolve_target(hit.get("collider")) != target:
		return {}
	return hit

func _is_agent_overlapping_traversable_body(
	target: BaseAgent,
	body: Object
) -> bool:
	var updraft := target.get_node_or_null("Components/UpdraftAbility")
	return (
		updraft != null
		and updraft.has_method("is_overlapping_traversable_body")
		and bool(updraft.call("is_overlapping_traversable_body", body))
	)

func _is_shooter_overlapping_traversable_body(body: Object) -> bool:
	if not shooter is BaseAgent:
		return false
	return _is_agent_overlapping_traversable_body(shooter as BaseAgent, body)

func _contains_hit_for_target(hits: Array[Dictionary], target: BaseAgent) -> bool:
	for hit in hits:
		if DamageSystem.resolve_target(hit.get("collider")) == target:
			return true
	return false

func _should_bullet_ignore_collider(collider: Object) -> bool:
	if not collider is CollisionObject2D:
		return false
	if collider is Wall or _is_bullet_penetrable_collider(collider):
		return false
	return ((collider as CollisionObject2D).collision_layer & BULLET_IGNORED_LAYER_MASK) != 0

func _is_platform_collider(collider: Object) -> bool:
	if not collider is CollisionObject2D:
		return false
	return ((collider as CollisionObject2D).collision_layer & PLATFORM_LAYER_MASK) != 0

func get_wall_cost(level: int) -> float:
	match level:
		Wall.PenetrationLevel.NONE:
			return INF
		Wall.PenetrationLevel.LOW:
			return 1.0
		Wall.PenetrationLevel.MEDIUM:
			return 2.0
		Wall.PenetrationLevel.HIGH:
			return 3.0
		_:
			return INF

func spawn_impact(hit_position: Vector2) -> void:
	var impact := BulletImpact.new()
	get_parent().add_child(impact)
	impact.global_position = hit_position

func get_damage_at_distance(travel_distance: float) -> float:
	# La bala recorre píxeles, pero WeaponData configura los umbrales en metros.
	var distance_meters: float = travel_distance / WeaponData.PIXELS_PER_METER
	if distance_meters <= short_range:
		return short_damage
	if distance_meters <= medium_range:
		return medium_damage
	return long_damage

func handle_hit(collider: Object, impact_distance: float, shape_index: int = -1) -> void:
	if network_visual_only:
		return
	DamageSystem.apply_hit(
		collider,
		get_damage_at_distance(impact_distance),
		shooter,
		weapon_name,
		true,
		shape_index
	)

func add_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject2D:
		rids.append(node.get_rid())
	for child in node.get_children():
		if child is Node:
			add_collision_rids(child, rids)
