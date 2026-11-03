extends Node

@export_group("Audio Timing")
@export_range(0.0, 2.0, 0.01, "suffix:s") var hurt_audio_quiet_period: float = 0.2

@export_group("Audio")
@export var hurt_audio: AudioCue

const HURT_AUDIO_CHANNEL: StringName = &"sage_hurt"

@onready var agent: BaseAgent = get_parent().get_parent() as BaseAgent

var hurt_audio_timer: Timer

func _ready() -> void:
	hurt_audio_timer = Timer.new()
	hurt_audio_timer.one_shot = true
	hurt_audio_timer.wait_time = hurt_audio_quiet_period
	hurt_audio_timer.timeout.connect(_play_hurt_audio_now)
	add_child(hurt_audio_timer)

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
