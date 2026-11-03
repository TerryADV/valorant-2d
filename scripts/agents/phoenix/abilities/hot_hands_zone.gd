extends DummyHazardArea

@export_range(0.1, 30.0, 0.1) var duration: float = 4.0
@export_range(0.0, 500.0, 1.0) var damage_per_second: float = 60.0
@export_range(0.01, 2.0, 0.01) var appear_duration: float = 0.2

var owner_peer_id := 1
var elapsed_time := 0.0
var initialized := false
var expiration_started := false
var original_scale := Vector2.ONE
var owner_healing_granted := false

func initialize(p_owner_peer_id: int) -> void:
	owner_peer_id = p_owner_peer_id
	original_scale = scale
	scale = Vector2.ZERO
	initialized = true
	var appear_tween := create_tween()
	appear_tween.tween_property(self, "scale", original_scale, appear_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if not initialized:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	elapsed_time += delta
	_apply_zone_damage(delta)
	if elapsed_time >= duration:
		_expire_zone()

func _expire_zone() -> void:
	if expiration_started:
		return
	expiration_started = true
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		remove_zone_rpc.rpc()
	else:
		queue_free()

@rpc("any_peer", "call_local", "reliable")
func remove_zone_rpc() -> void:
	if multiplayer.has_multiplayer_peer():
		var sender_id := multiplayer.get_remote_sender_id()
		if multiplayer.is_server():
			if sender_id != 0 and sender_id != 1:
				return
		elif sender_id != 1:
			return
	queue_free()

func _apply_zone_damage(delta: float) -> void:
	var owner_agent := NetworkManager.find_player(owner_peer_id)

	for body in get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		if body is BaseAgent and (body as BaseAgent).is_dead:
			continue
		if body == owner_agent:
			if not owner_healing_granted:
				owner_healing_granted = true
				var healing_component := owner_agent.get_node_or_null("Components/PhoenixHealing")
				if healing_component and healing_component.has_method("apply_healing_effect"):
					healing_component.call("apply_healing_effect", "Hot Hands")
			continue
		DamageSystem.apply_hit(body, damage_per_second * delta, owner_agent, "Hot Hands", false)
