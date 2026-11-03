extends Area2D

@export_group("Blade Projectile")
@export_range(1.0, 3000.0, 1.0, "suffix:px/s") var speed: float = 900.0
@export_range(1.0, 5000.0, 1.0, "suffix:px") var max_range: float = 1200.0
@export_range(0.0, 500.0, 1.0) var damage: float = 50.0
@export_range(0.0, 5.0, 0.05, "suffix:s") var trail_duration: float = 0.5
const HIT_MASK := 1 | 2 | 8 | 16 | 32

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var shooter: BaseAgent
var ability: Node
var direction := Vector2.RIGHT
var launch_position := Vector2.ZERO
var jett_color := Color(0.333333, 0.486275, 0.564706, 1.0)
var refill_on_kill := false
var is_projectile := false
var visual_only := false
var travelled := 0.0

func _ready() -> void:
	monitoring = false
	monitorable = false
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

func launch(
	p_shooter: BaseAgent,
	p_ability: Node,
	p_direction: Vector2,
	p_refill_on_kill: bool,
	p_visual_only: bool,
	p_color: Color
) -> void:
	shooter = p_shooter
	ability = p_ability
	direction = p_direction.normalized()
	launch_position = global_position
	refill_on_kill = p_refill_on_kill
	visual_only = p_visual_only
	jett_color = p_color
	rotation = direction.angle() + PI / 2.0
	is_projectile = true
	if collision_shape:
		collision_shape.set_deferred("disabled", visual_only)

func _physics_process(delta: float) -> void:
	if not is_projectile:
		return
	var step_distance := speed * delta
	var from_position := global_position
	var to_position := from_position + direction * step_distance
	if not visual_only:
		var query := PhysicsRayQueryParameters2D.create(from_position, to_position)
		query.collision_mask = HIT_MASK
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = _get_shooter_rids()
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			_resolve_server_impact(hit.collider, hit.position)
			return
	global_position = to_position
	travelled += step_distance
	if travelled >= max_range:
		if not visual_only:
			if multiplayer.has_multiplayer_peer():
				ability.rpc("sync_blade_impact_rpc", launch_id, global_position)
			else:
				ability.call("sync_blade_impact_rpc", launch_id, global_position)
			queue_free()

var launch_id := 0

func _resolve_server_impact(collider: Object, impact_position: Vector2) -> void:
	var target := DamageSystem.resolve_target(collider)
	var target_was_alive: bool = false
	if target is BaseAgent:
		target_was_alive = not target.is_dead
	if target_was_alive:
		DamageSystem.apply_hit(target, damage, shooter, "Blade Storm")
		var target_is_dead := false
		if target is BaseAgent:
			target_is_dead = target.is_dead or target.health_component.current_health <= 0.0
		if target_is_dead and refill_on_kill and ability:
			ability.call("award_dagger_kill")
	if multiplayer.has_multiplayer_peer():
		ability.rpc("sync_blade_impact_rpc", launch_id, impact_position)
	else:
		ability.call("sync_blade_impact_rpc", launch_id, impact_position)
	queue_free()

func _get_shooter_rids() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	if shooter:
		_append_collision_rids(shooter, excluded)
	return excluded

func _append_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject2D:
		rids.append((node as CollisionObject2D).get_rid())
	for child in node.get_children():
		_append_collision_rids(child, rids)

func create_trail(impact_position: Vector2) -> void:
	var trail := Line2D.new()
	trail.name = "BladeTrail"
	trail.add_to_group("skirmish_round_effects")
	trail.top_level = true
	trail.z_index = 15
	trail.width = 1.5
	trail.default_color = jett_color
	trail.add_point(launch_position)
	trail.add_point(impact_position)
	get_tree().current_scene.add_child(trail)
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, trail_duration)
	tween.tween_callback(trail.queue_free)
