extends Control

@onready var background: TextureRect = $TextureRect

func configure_for_match(mode: String, _ready_count: int, _player_count: int) -> void:
	var texture_path := (
		"res://assets/sprites/ui/loading_screen/skirmish/a.png"
		if mode == "skirmish"
		else "res://assets/sprites/ui/loading_screen/deathmach/ascent.png"
	)
	var texture := load(texture_path) as Texture2D
	if texture:
		background.texture = texture
