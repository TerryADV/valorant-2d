extends Area2D

const ZONE_DURATION := 7.0
const AGENT_COLLISION_MASK := 16

@export_range(0.01, 2.0, 0.01, "suffix:s") var appear_duration := 0.25
@export_range(0.01, 2.0, 0.01, "suffix:s") var disappear_duration := 0.25

var _target_scale := Vector2.ONE
var _is_expiring := false
var _affected_actors: Dictionary = {}

func _ready() -> void:
	collision_mask = AGENT_COLLISION_MASK
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_target_scale = scale
	scale = Vector2.ZERO
	var appear_tween := create_tween()
	var appear_tweener = appear_tween.tween_property(self, "scale", _target_scale, appear_duration)
	appear_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_expire_after_duration()

func _on_body_entered(body: Node2D) -> void:
	var agent := body as BaseAgent
	if agent:
		if agent.is_dead:
			return
		if agent.is_ai_dummy:
			_affected_actors[agent.get_instance_id()] = agent
			agent.set_slow_zone_active(get_instance_id(), true)
			return
		var movement_controller := agent.movement_controller as MovementController
		if not movement_controller:
			return
		_affected_actors[agent.get_instance_id()] = agent
		movement_controller.set_slow_zone_active(get_instance_id(), true)
		var died_callback := _on_agent_died.bind(agent)
		if not agent.died.is_connected(died_callback):
			agent.died.connect(died_callback, CONNECT_ONE_SHOT)
		return

func _on_body_exited(body: Node2D) -> void:
	_set_actor_slowed(body, false)

func _on_agent_died(agent: BaseAgent) -> void:
	_set_actor_slowed(agent, false)

func _set_actor_slowed(actor: Node2D, slowed: bool) -> void:
	if not is_instance_valid(actor):
		return
	if actor is BaseAgent and actor.is_ai_dummy:
		(actor as BaseAgent).set_slow_zone_active(get_instance_id(), slowed)
	elif actor is BaseAgent:
		var agent := actor as BaseAgent
		var movement_controller := agent.movement_controller as MovementController
		if movement_controller:
			movement_controller.set_slow_zone_active(get_instance_id(), slowed)
	if slowed:
		_affected_actors[actor.get_instance_id()] = actor
	else:
		_affected_actors.erase(actor.get_instance_id())

func _exit_tree() -> void:
	for actor in _affected_actors.values():
		_set_actor_slowed(actor as Node2D, false)

func _expire_after_duration() -> void:
	await get_tree().create_timer(ZONE_DURATION).timeout
	if not is_inside_tree():
		return
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			expire_zone_rpc.rpc()
	else:
		_begin_disappear()

@rpc("authority", "call_local", "reliable")
func expire_zone_rpc() -> void:
	_begin_disappear()

func _begin_disappear() -> void:
	if _is_expiring:
		return
	_is_expiring = true
	var disappear_tween := create_tween()
	var disappear_tweener = disappear_tween.tween_property(
		self, "scale", Vector2.ZERO, disappear_duration
	)
	disappear_tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	disappear_tween.tween_callback(queue_free)
