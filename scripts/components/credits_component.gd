class_name CreditsComponent
extends Node

signal credits_changed(current_credits: int)

@export_range(0, 99999, 100) var starting_credits: int = 9000

var current_credits: int
var infinite_credits_enabled := false

func _ready() -> void:
	current_credits = starting_credits
	credits_changed.emit(current_credits)
	set_process(true)

func _process(_delta: float) -> void:
	if infinite_credits_enabled and current_credits < 99999:
		set_credits(99999)

func set_infinite_credits_enabled(enabled: bool) -> void:
	infinite_credits_enabled = enabled
	if enabled:
		set_credits(99999)

func can_afford(amount: int) -> bool:
	return amount >= 0 and current_credits >= amount

func try_spend(amount: int) -> bool:
	if infinite_credits_enabled:
		set_credits(99999)
		return true
	if not can_afford(amount):
		return false
	current_credits -= amount
	credits_changed.emit(current_credits)
	return true

func set_credits(amount: int) -> void:
	current_credits = clampi(amount, 0, 99999)
	credits_changed.emit(current_credits)
