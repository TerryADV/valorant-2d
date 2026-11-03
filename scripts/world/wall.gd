class_name Wall
extends StaticBody2D

enum PenetrationLevel {
	NONE,
	LOW,
	MEDIUM,
	HIGH,
}

@export var penetration_level: PenetrationLevel = PenetrationLevel.MEDIUM

func get_penetration_level() -> PenetrationLevel:
	return penetration_level
