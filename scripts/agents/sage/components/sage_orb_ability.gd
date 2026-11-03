extends Node

const ORB_SCENE: PackedScene = preload("res://scenes/agents/sage/orb.tscn")
const BASIC_ABILITY_IDS: Array[String] = ["BarrierOrb", "SlowOrb", "HealingOrb"]
const ORB_INITIAL_SCALE_X := 0.016
const ORB_TARGET_SCALE_X := 0.024
const BARRIER_APPEAR_PHASE_RATIO := 0.5

@export_range(0.01, 2.0, 0.01, "suffix:s") var appear_duration := 0.5

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var held_orb: Area2D
var appear_tween: Tween
var is_appearing := false
var last_active_ability_id := ""

func handle_ability_input(event: InputEvent, input_action: String) -> bool:
	if not event.is_action_pressed(input_action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return true
	if is_appearing:
		return true
	var ability_index := agent.agent_data.ability_input_actions.find(input_action)
	if ability_index < 0 or ability_index >= BASIC_ABILITY_IDS.size():
		return true
	var ability_id := BASIC_ABILITY_IDS[ability_index]
	activate_ability(ability_id)
	get_viewport().set_input_as_handled()
	return true

func activate_ability(ability_id: String) -> bool:
	if is_appearing or not BASIC_ABILITY_IDS.has(ability_id):
		return false
	if not agent.has_ability_charge(ability_id):
		return false
	agent.set_active_ability(ability_id)
	if ability_id == "HealingOrb":
		var healing_ability := agent.get_node_or_null("Components/HealingOrbAbility")
		if healing_ability and healing_ability.has_method("play_cast_audio"):
			healing_ability.call("play_cast_audio")
	return true

func _process(_delta: float) -> void:
	if not agent:
		return
	on_agent_active_ability_changed(agent.active_ability_name)
	if is_instance_valid(held_orb):
		var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
		if weapon_pivot:
			held_orb.global_position = weapon_pivot.global_position
			held_orb.global_rotation = weapon_pivot.global_rotation

func on_agent_active_ability_changed(ability_name: String) -> void:
	if ability_name in BASIC_ABILITY_IDS:
		if ability_name != last_active_ability_id:
			last_active_ability_id = ability_name
			_update_weapon_visibility()
			_start_appearance()
	else:
		if not last_active_ability_id.is_empty():
			_update_weapon_visibility()
		last_active_ability_id = ""
		if not is_appearing and is_instance_valid(held_orb):
			held_orb.queue_free()
			held_orb = null
func blocks_weapon_input() -> bool:
	return is_appearing or (
		agent != null
		and agent.active_ability_name in BASIC_ABILITY_IDS
	)

func reset_for_new_round() -> void:
	if appear_tween and appear_tween.is_running():
		appear_tween.kill()
	is_appearing = false
	last_active_ability_id = ""
	if agent and agent.weapon_controller:
		agent.weapon_controller.set_weapon_hidden_by_ability(false)
	if is_instance_valid(held_orb):
		held_orb.queue_free()
	held_orb = null


func _start_appearance() -> void:
	if is_instance_valid(held_orb):
		held_orb.queue_free()
		held_orb = null
	if not is_instance_valid(held_orb):
		held_orb = ORB_SCENE.instantiate() as Area2D
		held_orb.name = "SageHeldOrb"
		held_orb.top_level = true
		held_orb.z_index = 4
		held_orb.monitoring = false
		held_orb.monitorable = false
		var orb_trail := held_orb.get_node_or_null("Line2D") as Line2D
		if orb_trail:
			orb_trail.visible = false
		var collision_shape := held_orb.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision_shape:
			collision_shape.disabled = true
		add_child(held_orb)
	if appear_tween and appear_tween.is_running():
		appear_tween.kill()
	var animate_barrier_stretch := agent.active_ability_name == "BarrierOrb"
	held_orb.modulate.a = 0.0
	var orb_sprite := held_orb.get_node_or_null("Sprite2D") as Sprite2D
	if orb_sprite and animate_barrier_stretch:
		orb_sprite.scale.x = ORB_INITIAL_SCALE_X
	var weapon_pivot := agent.get_node_or_null("Visuals/BodySprite/WeaponPivot") as Node2D
	if weapon_pivot:
		held_orb.global_position = weapon_pivot.global_position
		held_orb.global_rotation = weapon_pivot.global_rotation
	is_appearing = true
	appear_tween = create_tween()
	if animate_barrier_stretch:
		var phase_duration := appear_duration * BARRIER_APPEAR_PHASE_RATIO
		appear_tween.tween_property(held_orb, "modulate:a", 1.0, phase_duration)
		if orb_sprite:
			appear_tween.tween_property(
				orb_sprite, "scale:x", ORB_TARGET_SCALE_X, phase_duration
			).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		appear_tween.tween_property(held_orb, "modulate:a", 1.0, appear_duration)
	appear_tween.tween_callback(_finish_appearance)

func _finish_appearance() -> void:
	is_appearing = false
	if not agent or agent.active_ability_name not in BASIC_ABILITY_IDS:
		if is_instance_valid(held_orb):
			held_orb.queue_free()
		held_orb = null

func _update_weapon_visibility() -> void:
	if agent and agent.weapon_controller:
		agent.weapon_controller.set_weapon_hidden_by_ability(
			agent.active_ability_name in BASIC_ABILITY_IDS
		)
