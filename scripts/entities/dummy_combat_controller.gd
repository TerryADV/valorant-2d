extends RefCounted

const DIFFICULTY_EASY := 0
const DIFFICULTY_MEDIUM := 1
const EASY_AIM_TIME_MULTIPLIER := 0.75
const MEDIUM_AIM_TIME_MULTIPLIER := 0.4
const HARD_AIM_TIME_MULTIPLIER := 0.15
const SOUND_MELEE := 3
const BASE_FIRST_SHOT_SPREAD_DEGREES := 0.25
const BASE_WALK_SPREAD_DEGREES := 15.0
const BASE_RUN_SPREAD_DEGREES := 30.0
const MIN_PERCEPTION_INTERVAL := 0.12
const MAX_PERCEPTION_INTERVAL := 0.2

var _dummy: Node
var _available_weapons: Array[WeaponData] = []
var _perception_time_remaining := 0.0
var _cached_target_visible := false

func setup(dummy: Node, available_weapons: Array[WeaponData]) -> void:
	_dummy = dummy
	_available_weapons = available_weapons
	_perception_time_remaining = randf_range(0.0, MAX_PERCEPTION_INTERVAL)

func process_combat(delta: float) -> void:
	var multiplayer_api := _dummy.get_multiplayer()
	if multiplayer_api.has_multiplayer_peer() and not multiplayer_api.is_server():
		return
	var shoot_cooldown := maxf(0.0, float(_dummy.get("shoot_cooldown")) - delta)
	_dummy.set("shoot_cooldown", shoot_cooldown)
	var current_weapon := _dummy.get("current_weapon") as WeaponData
	var recoil_degrees := float(_dummy.get("recoil_degrees"))
	if current_weapon:
		recoil_degrees = move_toward(
			recoil_degrees,
			0.0,
			current_weapon.recoil_recovery_speed * delta
		)
		_dummy.set("recoil_degrees", recoil_degrees)

	var reload_remaining := float(_dummy.get("reload_time_remaining"))
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		_dummy.set("reload_time_remaining", reload_remaining)
		if reload_remaining == 0.0 and current_weapon and not current_weapon.is_melee:
			_dummy.set("ammo_in_magazine", current_weapon.magazine_size)
	if not current_weapon or _dummy.is_queued_for_deletion():
		return

	var target_actor := _dummy.get("target_actor") as Node2D
	_perception_time_remaining -= delta
	if _perception_time_remaining <= 0.0:
		_perception_time_remaining = randf_range(
			MIN_PERCEPTION_INTERVAL, MAX_PERCEPTION_INTERVAL
		)
		if is_combat_target_valid(target_actor) and can_see_target(target_actor):
			_cached_target_visible = true
		else:
			var newly_visible_target := find_nearest_opponent()
			if newly_visible_target:
				target_actor = newly_visible_target
				_dummy.set("target_actor", target_actor)
				_cached_target_visible = true
			else:
				_cached_target_visible = false
				if not is_combat_target_valid(target_actor):
					target_actor = null
					_dummy.set("target_actor", null)
		if target_actor and _cached_target_visible:
			_remember_target_position(target_actor)
	elif is_combat_target_valid(target_actor):
		_remember_target_position(target_actor)
	if not is_combat_target_valid(target_actor) or not _cached_target_visible:
		(_dummy.get("_dummy_controller") as RefCounted).reset_aim()
		return

	var dummy_position := (_dummy as Node2D).global_position
	var to_target := target_actor.global_position - dummy_position
	_dummy.set("wait_time_remaining", 0.0)
	var attack_distance := _get_attack_distance(current_weapon)
	if to_target.length() > attack_distance:
		(_dummy.get("_dummy_controller") as RefCounted).reset_aim()
		return

	var visuals := _dummy.get("visuals") as Node2D
	visuals.rotation = to_target.angle() + PI / 2.0
	if reload_remaining > 0.0:
		(_dummy.get("_dummy_controller") as RefCounted).reset_aim()
		return
	if current_weapon.can_aim:
		var aim_target := _dummy.get("aim_target") as Node2D
		if not bool(_dummy.get("is_aiming")) or aim_target != target_actor:
			_dummy.set("is_aiming", true)
			_dummy.set("aim_target", target_actor)
			_dummy.set(
				"aim_time_remaining",
				float(_dummy.get("aim_time")) * _get_aim_time_multiplier()
			)
		var aim_time_remaining := float(_dummy.get("aim_time_remaining"))
		if aim_time_remaining > 0.0:
			_dummy.set("aim_time_remaining", maxf(0.0, aim_time_remaining - delta))
			return
	else:
		(_dummy.get("_dummy_controller") as RefCounted).reset_aim()

	if shoot_cooldown > 0.0:
		return
	if current_weapon.is_melee:
		DamageSystem.apply_hit(
			target_actor,
			current_weapon.melee_light_damage,
			_dummy,
			current_weapon.weapon_name
		)
		(_dummy.get("_dummy_controller") as RefCounted).call_weapon("play_weapon_cue", [SOUND_MELEE, dummy_position])
		_dummy.set("shoot_cooldown", current_weapon.melee_light_cooldown)
		return
	if int(_dummy.get("ammo_in_magazine")) <= 0:
		_dummy.set("reload_time_remaining", current_weapon.reload_time)
		(_dummy.get("_dummy_controller") as RefCounted).call_weapon("play_reload_sound")
		return

	fire_at_target(to_target.normalized())
	_dummy.set("ammo_in_magazine", int(_dummy.get("ammo_in_magazine")) - 1)
	var aim_fire_rate_multiplier := current_weapon.aim_fire_rate_multiplier if bool(_dummy.get("is_aiming")) else 1.0
	var fire_rate := current_weapon.fire_rate * aim_fire_rate_multiplier * get_fire_rate_multiplier()
	_dummy.set("shoot_cooldown", 1.0 / maxf(fire_rate, 0.1))

func get_fire_rate_multiplier() -> float:
	match int(_dummy.get("difficulty")):
		DIFFICULTY_EASY:
			return 0.25
		DIFFICULTY_MEDIUM:
			return 0.5
		_:
			return 1.0

func _get_aim_time_multiplier() -> float:
	match int(_dummy.get("difficulty")):
		DIFFICULTY_EASY:
			return EASY_AIM_TIME_MULTIPLIER
		DIFFICULTY_MEDIUM:
			return MEDIUM_AIM_TIME_MULTIPLIER
		_:
			return HARD_AIM_TIME_MULTIPLIER

func find_nearest_opponent() -> Node2D:
	var nearest_opponent: Node2D
	var nearest_distance := INF
	for actor in _dummy.get_tree().get_nodes_in_group("combat_actors"):
		var opponent := actor as Node2D
		if opponent == _dummy or not is_combat_target_valid(opponent) or not can_see_target(opponent):
			continue
		var distance := (_dummy as Node2D).global_position.distance_squared_to(opponent.global_position)
		if distance < nearest_distance:
			nearest_opponent = opponent
			nearest_distance = distance
	return nearest_opponent

func _remember_target_position(target: Node2D) -> void:
	_dummy.set("last_known_target_position", target.global_position)
	_dummy.set("has_last_known_target_position", true)

func find_nearest_opponent_in(node: Node) -> Node2D:
	var nearest_opponent: Node2D
	var nearest_distance := INF
	if node.has_method("get_deathmatch_id"):
		var opponent := node as Node2D
		if (
			opponent != _dummy
			and is_combat_target_valid(opponent)
			and can_see_target(opponent)
		):
			nearest_opponent = opponent
			nearest_distance = (_dummy as Node2D).global_position.distance_squared_to(opponent.global_position)

	for child in node.get_children():
		var opponent := find_nearest_opponent_in(child)
		if opponent:
			var distance := (_dummy as Node2D).global_position.distance_squared_to(opponent.global_position)
			if distance < nearest_distance:
				nearest_opponent = opponent
				nearest_distance = distance
	return nearest_opponent

func is_combat_target_valid(target: Node2D) -> bool:
	if not is_instance_valid(target) or target == _dummy or target.is_queued_for_deletion():
		return false
	var dummy_team := int(_dummy.get("skirmish_team"))
	if dummy_team >= 0 and int(target.get("skirmish_team")) == dummy_team:
		return false
	if target.has_method("get_deathmatch_id"):
		return not bool(target.get("is_dead"))
	return false

func can_see_target(target: Node2D) -> bool:
	var position := (_dummy as Node2D).global_position
	return (
		is_combat_target_valid(target)
		and position.distance_squared_to(target.global_position)
		<= float(_dummy.get("vision_range")) * float(_dummy.get("vision_range"))
		and has_line_of_sight(target)
	)

func has_line_of_sight(target: Node2D) -> bool:
	var dummy_node := _dummy as Node2D
	var query := PhysicsRayQueryParameters2D.create(dummy_node.global_position, target.global_position)
	query.collision_mask = 1 | 2
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var excluded_rids: Array[RID] = [(_dummy as CollisionObject2D).get_rid()]
	query.exclude = excluded_rids
	var line_clear := false
	for _raycast_attempt in 32:
		var hit := dummy_node.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			line_clear = true
			break
		var collider := hit.get("collider") as Node
		if _is_target_overlapping_traversable_body(target, collider):
			line_clear = true
			break
		return false
	if not line_clear:
		return false
	for occluder in _dummy.get_tree().get_nodes_in_group("vision_occluders"):
		if (
			occluder is Node2D
			and not _is_target_overlapping_traversable_body(target, occluder)
			and occluder.has_method("blocks_vision")
			and bool(occluder.call("blocks_vision", dummy_node.global_position, target.global_position))
		):
			return false
	return true

func _is_target_overlapping_traversable_body(target: Node2D, collider: Object) -> bool:
	if not target.has_method("get_deathmatch_id"):
		return false
	if not collider is PhysicsBody2D:
		return false
	var updraft := target.get_node_or_null("Components/UpdraftAbility")
	return (
		updraft != null
		and updraft.has_method("is_overlapping_traversable_body")
		and bool(updraft.call("is_overlapping_traversable_body", collider))
	)

func can_attack_target() -> bool:
	var target_actor := _dummy.get("target_actor") as Node2D
	var current_weapon := _dummy.get("current_weapon") as WeaponData
	if (
		not current_weapon
		or not _cached_target_visible
		or not is_combat_target_valid(target_actor)
	):
		return false
	var attack_distance := _get_attack_distance(current_weapon)
	return (_dummy as Node2D).global_position.distance_to(target_actor.global_position) <= attack_distance

func _get_attack_distance(weapon: WeaponData) -> float:
	if weapon.is_melee:
		return weapon.melee_range
	var weapon_type := weapon.weapon_type.to_lower()
	match weapon_type:
		"shotgun":
			return 80.0
		"sniper":
			return 320.0
		"rifle":
			return 160.0
		"smg":
			return 120.0
		"sidearm", "heavy":
			return 160.0
		_:
			return float(_dummy.get("shooting_range"))

func fire_at_target(direction: Vector2) -> void:
	var current_weapon := _dummy.get("current_weapon") as WeaponData
	var pellet_count := maxi(current_weapon.pellets_per_shot, 1)
	var spread := BASE_FIRST_SHOT_SPREAD_DEGREES
	var walk_speed := float(_dummy.get("run_speed")) * 0.6
	var current_speed := Vector2(_dummy.get("velocity")).length()
	if current_speed > walk_speed + 10.0:
		spread = BASE_RUN_SPREAD_DEGREES
	elif current_speed > 10.0:
		spread = BASE_WALK_SPREAD_DEGREES

	var is_aiming := bool(_dummy.get("is_aiming"))
	var recoil_multiplier := current_weapon.aim_recoil_multiplier if is_aiming else 1.0
	var recoil_variation := randf_range(
		-current_weapon.recoil_randomness_degrees,
		current_weapon.recoil_randomness_degrees
	)
	var total_spread := (
		spread
		+ current_weapon.pellet_spread_degrees
		+ (current_weapon.hipfire_spread_degrees if not is_aiming else 0.0)
		+ float(_dummy.get("shooting_spread_degrees"))
		+ float(_dummy.get("recoil_degrees")) * recoil_multiplier
		+ recoil_variation * recoil_multiplier
	)
	_dummy.set(
		"recoil_degrees",
		minf(
			float(_dummy.get("recoil_degrees"))
			+ current_weapon.recoil_per_shot_degrees * recoil_multiplier,
			current_weapon.max_recoil_degrees
		)
	)
	var start_position := (_dummy as Node2D).global_position + direction * 8.0
	for pellet_index in pellet_count:
		var pellet_direction := direction.rotated(deg_to_rad(randf_range(-total_spread, total_spread)))
		if _dummy.get_multiplayer().has_multiplayer_peer():
			_dummy.rpc(
				"sync_dummy_bullet",
				_available_weapons.find(current_weapon),
				start_position,
				pellet_direction,
				pellet_index == 0
			)
		else:
			(_dummy.get("_dummy_controller") as RefCounted).call_weapon(
				"spawn_bullet",
				[current_weapon, start_position, pellet_direction, false, pellet_index == 0]
			)
