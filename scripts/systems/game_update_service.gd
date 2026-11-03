extends RefCounted

signal download_progress(bytes_received: int, total_bytes: int)

const RELEASE_API_URL := "https://api.github.com/repos/TerryADV/valorant-2d/releases/latest"
const PATCH_ASSET_NAME := "valorant2d-patch.pck"
const REQUEST_HEADERS := PackedStringArray([
	"Accept: application/vnd.github+json",
	"X-GitHub-Api-Version: 2022-11-28",
	"User-Agent: Valorant2D-Updater"
])
const UPDATE_STATE_PATH := "user://installed_update.cfg"
const PENDING_UPDATE_PATH := "user://pending_update.cfg"

var _owner: Node
var _release_request: HTTPRequest
var _download_request: HTTPRequest
var _request_finished := false
var _request_response: Array = []

func setup(owner: Node) -> void:
	_owner = owner
	_release_request = HTTPRequest.new()
	_download_request = HTTPRequest.new()
	_release_request.timeout = 20.0
	_download_request.timeout = 0.0
	_owner.add_child(_release_request)
	_owner.add_child(_download_request)

func get_installed_version(project_version: String) -> String:
	var state := ConfigFile.new()
	if state.load(UPDATE_STATE_PATH) == OK:
		return str(state.get_value("update", "version", project_version))
	return project_version

func check_and_download_update(current_version: String) -> Dictionary:
	var request_error := _release_request.request(RELEASE_API_URL, REQUEST_HEADERS)
	if request_error != OK:
		return _result("error", "Could not contact the update service.")

	var response: Array = await _release_request.request_completed
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return _result("error", "Could not check for updates.")

	var parser := JSON.new()
	var response_body: PackedByteArray = response[3]
	var parse_error := parser.parse(response_body.get_string_from_utf8())
	if parse_error != OK or not parser.data is Dictionary:
		return _result("error", "The update service returned invalid data.")

	var release: Dictionary = parser.data
	var remote_version := str(release.get("tag_name", "")).trim_prefix("v")
	if remote_version.is_empty():
		return _result("error", "The latest release has no version tag.")
	var release_summary := _get_release_summary(release, remote_version)
	if not _is_version_newer(remote_version, current_version):
		if _is_version_newer(current_version, remote_version):
			return _result(
				"newer_local_build",
				"Build %s is newer than the latest release, %s." % [current_version, release_summary]
			)
		return _result("up_to_date", release_summary)

	var patch_asset := _find_patch_asset(release.get("assets", []))
	if patch_asset.is_empty():
		return _result(
			"package_missing",
			"%s Update package not published yet." % release_summary,
			remote_version
		)

	var update_directory := "user://updates"
	var absolute_directory := ProjectSettings.globalize_path(update_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _result("error", "Could not create the update folder.")

	var patch_path := "%s/valorant2d_%s.pck" % [update_directory, remote_version]
	_download_request.download_file = patch_path
	var download_error := _download_request.request(
		str(patch_asset.get("browser_download_url", "")), REQUEST_HEADERS
	)
	if download_error != OK:
		return _result("error", "Could not start downloading the update.")

	var total_bytes := int(patch_asset.get("size", 0))
	var download_response: Array = await _wait_for_download(total_bytes)
	_download_request.download_file = ""
	if int(download_response[0]) != HTTPRequest.RESULT_SUCCESS or int(download_response[1]) != 200:
		return _result("error", "The update download failed.")
	if not _matches_release_digest(patch_path, str(patch_asset.get("digest", ""))):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(patch_path))
		return _result("error", "The downloaded update failed its integrity check.")

	var pending := ConfigFile.new()
	pending.set_value("update", "version", remote_version)
	pending.set_value("update", "path", patch_path)
	var save_error := pending.save(PENDING_UPDATE_PATH)
	if save_error != OK:
		return _result("error", "Could not prepare the downloaded update.")
	return _result("downloaded", "Update %s downloaded. Restart the game to install it." % remote_version, remote_version)

func _wait_for_download(total_bytes: int) -> Array:
	_request_finished = false
	_request_response.clear()
	_download_request.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)
	while not _request_finished:
		download_progress.emit(_download_request.get_downloaded_bytes(), total_bytes)
		await _owner.get_tree().process_frame
	return _request_response

func _on_download_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_request_response = [result, response_code]
	_request_finished = true

func _find_patch_asset(assets_value: Variant) -> Dictionary:
	if not assets_value is Array:
		return {}
	for asset_value in assets_value:
		if asset_value is Dictionary and str(asset_value.get("name", "")) == PATCH_ASSET_NAME:
			return asset_value
	return {}

func _get_release_summary(release: Dictionary, version: String) -> String:
	var summary := str(release.get("body", "")).strip_edges()
	if summary.is_empty():
		summary = str(release.get("name", "New update"))
	else:
		summary = summary.split("\n", false)[0].strip_edges()
	if summary.length() > 32:
		summary = "%s..." % summary.substr(0, 29)
	return "Latest v%s: %s" % [version, summary]

func _matches_release_digest(path: String, digest: String) -> bool:
	if not digest.begins_with("sha256:"):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return false
	while file.get_position() < file.get_length():
		var chunk := file.get_buffer(65536)
		if chunk.is_empty():
			break
		hash_context.update(chunk)
	file.close()
	return hash_context.finish().hex_encode().to_lower() == digest.trim_prefix("sha256:").to_lower()

func _is_version_newer(candidate: String, installed: String) -> bool:
	var candidate_parts := _version_parts(candidate)
	var installed_parts := _version_parts(installed)
	var part_count := maxi(candidate_parts.size(), installed_parts.size())
	for index in range(part_count):
		var candidate_part := int(candidate_parts[index]) if index < candidate_parts.size() else 0
		var installed_part := int(installed_parts[index]) if index < installed_parts.size() else 0
		if candidate_part != installed_part:
			return candidate_part > installed_part
	return false

func _version_parts(version: String) -> PackedStringArray:
	return version.trim_prefix("v").split(".")

func _result(status: String, message: String, version: String = "") -> Dictionary:
	return {"status": status, "message": message, "version": version}
