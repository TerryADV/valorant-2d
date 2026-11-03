class_name GameModeSelector
extends Node

enum Mode {
	NORMAL,
	DEATHMATCH,
	SKIRMISH,
}

@export var selected_mode: Mode = Mode.NORMAL

func is_deathmatch() -> bool:
	return selected_mode == Mode.DEATHMATCH

func is_normal() -> bool:
	return selected_mode == Mode.NORMAL

func is_skirmish() -> bool:
	return selected_mode == Mode.SKIRMISH

func get_mode_name() -> String:
	if is_deathmatch():
		return "Deathmatch"
	if is_skirmish():
		return "Skirmish"
	return "Normal"
