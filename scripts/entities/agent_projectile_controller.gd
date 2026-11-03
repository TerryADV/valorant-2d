extends RefCounted

var _agent: Node

func setup(agent: Node) -> void:
	_agent = agent

func handle_bullet_request(
	start_position: Vector2,
	direction: Vector2,
	wall_penetration: String,
	tracer_enabled: bool,
	weapon_name: String,
	short_range: float,
	medium_range: float,
	short_damage: float,
	medium_damage: float,
	long_damage: float,
	play_shot_sound: bool,
	is_secondary_fire: bool
) -> void:
	var multiplayer_api := _agent.get_multiplayer()
	if not multiplayer_api.is_server():
		return
	if multiplayer_api.get_remote_sender_id() != _agent.get_multiplayer_authority():
		return
	_agent.rpc(
		"spawn_network_bullet",
		start_position,
		direction,
		wall_penetration,
		tracer_enabled,
		weapon_name,
		short_range,
		medium_range,
		short_damage,
		medium_damage,
		long_damage,
		play_shot_sound,
		is_secondary_fire
	)

func spawn_bullet(
	start_position: Vector2,
	direction: Vector2,
	wall_penetration: String,
	tracer_enabled: bool,
	weapon_name: String,
	short_range: float,
	medium_range: float,
	short_damage: float,
	medium_damage: float,
	long_damage: float,
	play_shot_sound: bool,
	is_secondary_fire: bool
) -> void:
	var weapon_controller: Node = _agent.get("weapon_controller")
	if play_shot_sound:
		var shot_weapon := weapon_controller.call("get_weapon_by_name", weapon_name) as WeaponData
		var shot_audio: AudioCue = (
			shot_weapon.secondary_shot_audio
			if shot_weapon and is_secondary_fire and shot_weapon.secondary_shot_audio
			else shot_weapon.shot_audio
			if shot_weapon
			else null
		)
		if (
			shot_weapon
			and not (
				_agent.is_multiplayer_authority()
				and shot_weapon.shot_local_audio
				and not is_secondary_fire
			)
		):
			AudioManager.play_world_cue(shot_audio, start_position)

	var bullet_scene := preload("res://scenes/weapons/bullet.tscn")
	var bullet := bullet_scene.instantiate() as Bullet
	bullet.init_bullet(
		start_position,
		direction,
		_agent as Node2D,
		wall_penetration,
		weapon_name,
		short_range,
		medium_range,
		short_damage,
		medium_damage,
		long_damage
	)
	bullet.set_tracer_enabled(tracer_enabled or _agent.is_multiplayer_authority())
	bullet.network_visual_only = (
		_agent.get_multiplayer().has_multiplayer_peer()
		and not _agent.get_multiplayer().is_server()
	)
	_agent.get_parent().add_child(bullet)
