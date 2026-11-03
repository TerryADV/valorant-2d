extends Node

const PENDING_UPDATE_PATH := "user://pending_update.cfg"
const INSTALLED_UPDATE_PATH := "user://installed_update.cfg"

func _init() -> void:
	var pending := ConfigFile.new()
	if pending.load(PENDING_UPDATE_PATH) != OK:
		return

	var pack_path := str(pending.get_value("update", "path", ""))
	var version := str(pending.get_value("update", "version", ""))
	if pack_path.is_empty() or version.is_empty() or not FileAccess.file_exists(pack_path):
		return
	if not ProjectSettings.load_resource_pack(pack_path, true):
		push_error("Could not load the downloaded game update: %s" % pack_path)
		return

	var installed := ConfigFile.new()
	installed.set_value("update", "version", version)
	var save_error := installed.save(INSTALLED_UPDATE_PATH)
	if save_error != OK:
		push_error("Could not save the installed game version: %s" % error_string(save_error))
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_UPDATE_PATH))
