class_name AudioCue
extends Resource

enum PlaybackType {
	LOCAL,
	TEAM,
	RANGE,
	GLOBAL,
}

@export var playback_type: PlaybackType = PlaybackType.RANGE
@export var stream: AudioStream
@export_range(1.0, 1000.0, 1.0, "suffix:px") var max_distance: float = 100.0
@export_range(0.0, 4.0, 0.05) var attenuation: float = 1.0
@export_range(-20.0, 20.0, 0.5, "suffix:dB") var volume_db: float = 0.0
@export_range(0.1, 3.0, 0.01) var pitch_min: float = 1.0
@export_range(0.1, 3.0, 0.01) var pitch_max: float = 1.0
