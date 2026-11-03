class_name HealthComponent
extends Node

signal health_changed(current_health: float, max_health: float)
signal damage_taken(amount: float)
signal died
signal regenerative_shield_state_changed(active: bool, regenerating: bool, reserve: float, max_reserve: float)

const REGENERATIVE_SHIELD_CAPACITY := 25.0
const REGENERATIVE_RESERVE_CAPACITY := 50.0
const REGENERATIVE_RECHARGE_DELAY := 3.0
const REGENERATIVE_RECHARGE_RATE := 25.0
const REGENERATIVE_RECHARGE_TICK := 0.1

@export var max_health: float = 100.0
@export var max_shield: float = 50.0

var current_health: float
var current_shield: float
var regenerative_shield_active := false
var regenerative_shield_reserve := 0.0
var regenerative_recharge_delay_remaining := 0.0
var _regenerative_recharge_tick_elapsed := 0.0

func _ready() -> void:
	current_health = max_health
	current_shield = max_shield

func _process(delta: float) -> void:
	if not regenerative_shield_active or regenerative_shield_reserve <= 0.0:
		return
	var multiplayer_api := get_multiplayer()
	if multiplayer_api.has_multiplayer_peer():
		var owner_node := get_damage_owner()
		if not owner_node or not owner_node.is_multiplayer_authority():
			return
	if regenerative_recharge_delay_remaining > 0.0:
		regenerative_recharge_delay_remaining = maxf(regenerative_recharge_delay_remaining - delta, 0.0)
		return
	if current_shield >= REGENERATIVE_SHIELD_CAPACITY:
		return
	_regenerative_recharge_tick_elapsed += delta
	while _regenerative_recharge_tick_elapsed >= REGENERATIVE_RECHARGE_TICK:
		_regenerative_recharge_tick_elapsed -= REGENERATIVE_RECHARGE_TICK
		_regenerate_shield_tick()
		if regenerative_shield_reserve <= 0.0 or current_shield >= REGENERATIVE_SHIELD_CAPACITY:
			break

func _regenerate_shield_tick() -> void:
	var restored := minf(
		REGENERATIVE_RECHARGE_RATE * REGENERATIVE_RECHARGE_TICK,
		minf(regenerative_shield_reserve, REGENERATIVE_SHIELD_CAPACITY - current_shield)
	)
	if restored <= 0.0:
		return
	current_shield += restored
	regenerative_shield_reserve -= restored
	regenerative_shield_state_changed.emit(
		true,
		_is_regenerative_shield_regenerating(),
		regenerative_shield_reserve,
		REGENERATIVE_RESERVE_CAPACITY
	)
	health_changed.emit(current_health, max_health)

func activate_regenerative_shield() -> void:
	regenerative_shield_active = true
	regenerative_shield_reserve = REGENERATIVE_RESERVE_CAPACITY
	regenerative_recharge_delay_remaining = 0.0
	_regenerative_recharge_tick_elapsed = 0.0
	current_shield = REGENERATIVE_SHIELD_CAPACITY
	regenerative_shield_state_changed.emit(true, false, regenerative_shield_reserve, REGENERATIVE_RESERVE_CAPACITY)
	health_changed.emit(current_health, max_health)

func deactivate_regenerative_shield() -> void:
	regenerative_shield_active = false
	regenerative_shield_reserve = 0.0
	regenerative_recharge_delay_remaining = 0.0
	_regenerative_recharge_tick_elapsed = 0.0
	regenerative_shield_state_changed.emit(false, false, 0.0, REGENERATIVE_RESERVE_CAPACITY)

func get_regenerative_shield_state() -> Dictionary:
	return {
		"active": regenerative_shield_active,
		"regenerating": _is_regenerative_shield_regenerating(),
		"reserve": regenerative_shield_reserve,
		"max_reserve": REGENERATIVE_RESERVE_CAPACITY,
	}

func _is_regenerative_shield_regenerating() -> bool:
	return (
		regenerative_shield_active
		and regenerative_shield_reserve > 0.0
		and regenerative_recharge_delay_remaining <= 0.0
		and current_shield < REGENERATIVE_SHIELD_CAPACITY
	)

func configure_health(p_max_health: float, p_max_shield: float) -> void:
	max_health = maxf(0.0, p_max_health)
	max_shield = maxf(0.0, p_max_shield)
	current_health = max_health
	current_shield = max_shield
	health_changed.emit(current_health, max_health)

func reset_health() -> void:
	current_health = max_health
	current_shield = REGENERATIVE_SHIELD_CAPACITY if regenerative_shield_active else max_shield
	if regenerative_shield_active:
		regenerative_shield_reserve = REGENERATIVE_RESERVE_CAPACITY
		regenerative_recharge_delay_remaining = 0.0
		_regenerative_recharge_tick_elapsed = 0.0
		regenerative_shield_state_changed.emit(true, false, regenerative_shield_reserve, REGENERATIVE_RESERVE_CAPACITY)
	health_changed.emit(current_health, max_health)

func restore_state(
	health: float,
	shield: float,
	regenerative_reserve: float = -1.0,
	regenerative_delay: float = -1.0
) -> void:
	current_health = clampf(health, 0.0, max_health)
	current_shield = clampf(shield, 0.0, max_shield)
	if regenerative_reserve >= 0.0:
		regenerative_shield_reserve = clampf(regenerative_reserve, 0.0, REGENERATIVE_RESERVE_CAPACITY)
	if regenerative_delay >= 0.0:
		regenerative_recharge_delay_remaining = regenerative_delay
	regenerative_shield_state_changed.emit(
		regenerative_shield_active,
		_is_regenerative_shield_regenerating(),
		regenerative_shield_reserve,
		REGENERATIVE_RESERVE_CAPACITY
	)
	health_changed.emit(current_health, max_health)

func set_current_shield(shield_amount: float) -> void:
	current_shield = clampf(shield_amount, 0.0, max_shield)
	health_changed.emit(current_health, max_health)

func heal(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	var healed_health := minf(max_health, current_health + amount)
	if is_equal_approx(healed_health, current_health):
		return
	current_health = healed_health
	health_changed.emit(current_health, max_health)

func take_damage(amount: float) -> void:
	if current_health <= 0:
		return
	var owner_node: Node = get_damage_owner()
	if owner_node and owner_node.has_method("is_invulnerable") and owner_node.is_invulnerable():
		return

	if regenerative_shield_active:
		var shield_absorbed := minf(current_shield, amount)
		current_shield -= shield_absorbed
		current_health = maxf(0.0, current_health - (amount - shield_absorbed))
		if regenerative_shield_reserve > 0.0 and amount > 0.0:
			regenerative_recharge_delay_remaining = REGENERATIVE_RECHARGE_DELAY
			_regenerative_recharge_tick_elapsed = 0.0
			regenerative_shield_state_changed.emit(
				true, false, regenerative_shield_reserve, REGENERATIVE_RESERVE_CAPACITY
			)
	elif current_shield > 0.0:
		var shield_damage: float = amount * 0.66
		var health_damage: float = amount * 0.34
		var absorbed: float = minf(current_shield, shield_damage)
		current_shield -= absorbed
		health_damage += shield_damage - absorbed
		current_health = maxf(0.0, current_health - health_damage)
	else:
		current_health = maxf(0.0, current_health - amount)

	health_changed.emit(current_health, max_health)
	damage_taken.emit(amount)

	if owner_node is CanvasItem:
		var flash_color := Color(1.0, 0.2, 0.2, 1.0)
		var tween := create_tween()
		tween.tween_property(owner_node, "modulate", flash_color, 0.05)
		tween.tween_property(owner_node, "modulate", Color.WHITE, 0.1)

	if current_health <= 0.0:
		died.emit()
		on_death()

func on_death() -> void:
	var owner_node: Node = get_damage_owner()
	if owner_node:
		if owner_node.has_method("handle_death"):
			owner_node.handle_death()
			return
		var tween := create_tween()
		tween.tween_property(owner_node, "modulate:a", 0.0, 0.2)
		tween.tween_callback(owner_node.queue_free)

func get_damage_owner() -> Node:
	var current: Node = get_parent()
	while current:
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null
