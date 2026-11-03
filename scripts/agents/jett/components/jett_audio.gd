extends Node

@export_group("Audio Timing")
@export_range(0.0, 2.0, 0.01, "suffix:s") var hurt_audio_quiet_period: float = 0.2
@export_range(0.0, 2.0, 0.01, "suffix:s") var healing_audio_quiet_period: float = 0.25
const HURT_AUDIO_CHANNEL: StringName = &"jett_hurt"
const HEALING_AUDIO_CHANNEL: StringName = &"jett_healing"

@export_group("Audio")
@export var hurt_audio: AudioCue
@export var healing_audio: AudioCue

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var hurt_audio_timer: Timer
var healing_audio_timer: Timer
var healing_audio_playing := false
var last_health := 0.0

func _ready() -> void:
	hurt_audio_timer = _create_timer(hurt_audio_quiet_period, _play_hurt_audio_now)
	healing_audio_timer = _create_timer(
		healing_audio_quiet_period,
		_stop_healing_audio
	)
	last_health = agent.health_component.current_health
	if not agent.health_component.health_changed.is_connected(_on_health_changed):
		agent.health_component.health_changed.connect(_on_health_changed)

func _exit_tree() -> void:
	if is_instance_valid(healing_audio_timer):
		healing_audio_timer.stop()
	if healing_audio_playing and is_instance_valid(agent) and agent.has_local_authority():
		AudioManager.stop_local_cue(HEALING_AUDIO_CHANNEL)

func schedule_hurt_audio_locally() -> void:
	if not agent or not agent.has_local_authority():
		return
	if agent.is_dead or agent.health_component.current_health <= 0.0:
		hurt_audio_timer.stop()
		return
	hurt_audio_timer.start()

func _play_hurt_audio_now() -> void:
	if (
		agent
		and agent.has_local_authority()
		and not agent.is_dead
		and agent.health_component.current_health > 0.0
		and hurt_audio
		and hurt_audio.stream
	):
		AudioManager.play_local_cue(hurt_audio, HURT_AUDIO_CHANNEL)

func _on_health_changed(current_health: float, _max_health: float) -> void:
	var health_increased := current_health > last_health
	last_health = current_health
	if not agent.has_local_authority():
		return
	if health_increased and not agent.is_dead and not agent.is_match_preparing:
		_start_or_refresh_healing_audio()

func _start_or_refresh_healing_audio() -> void:
	if not healing_audio or not healing_audio.stream:
		return
	if not healing_audio_playing:
		AudioManager.play_local_loop_cue(healing_audio, HEALING_AUDIO_CHANNEL)
		healing_audio_playing = true
	healing_audio_timer.start()

func _stop_healing_audio() -> void:
	if not healing_audio_playing:
		return
	AudioManager.stop_local_cue(HEALING_AUDIO_CHANNEL)
	healing_audio_playing = false

func _create_timer(wait_time: float, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = wait_time
	timer.timeout.connect(callback)
	add_child(timer)
	return timer
