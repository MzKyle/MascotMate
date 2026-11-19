extends RefCounted

var repo_root := ""
var helper_pid := -1
var last_error := ""
var _session_file: FileAccess


func configure(root: String) -> void:
	repo_root = root


func is_running() -> bool:
	if helper_pid > 0 and OS.is_process_running(helper_pid):
		return true
	stop()
	return false


func open_in_browser(args: PackedStringArray) -> bool:
	last_error = ""
	if is_running():
		var url_path := _session_file.get_path_absolute() + ".url"
		if not FileAccess.file_exists(url_path):
			# The first launch will open the browser when the helper is ready.
			return true
		var url := FileAccess.get_file_as_string(url_path)
		if _open_url(url) == OK:
			return true
		last_error = "open_failed"
		return false

	var command = _helper_command(args)
	if command.is_empty():
		last_error = "not_found"
		return false
	_session_file = FileAccess.create_temp(FileAccess.WRITE, "mascotmate-helper", "session")
	if _session_file == null:
		last_error = "start_failed"
		return false
	var process_args: PackedStringArray = command["args"]
	process_args.append_array(["--session-file", _session_file.get_path_absolute()])
	helper_pid = OS.create_process(str(command["program"]), process_args, false)
	if helper_pid <= 0:
		last_error = "start_failed"
		stop()
		return false
	return true


func stop() -> void:
	# Releasing the session file asks the server itself to exit. This also
	# works when the tracked PID is the one-file bundle's bootloader.
	_session_file = null
	helper_pid = -1


func _open_url(url: String) -> Error:
	# Only open the loopback console or store URL published by the helper.
	var pattern := RegEx.create_from_string("^http://127\\.0\\.0\\.1:[0-9]{1,5}/(companion/)?\\?token=[A-Za-z0-9_-]+$")
	return OS.shell_open(url) if pattern.search(url) != null else ERR_INVALID_DATA


func _helper_command(args: PackedStringArray) -> Dictionary:
	var helper = _helper_path()
	if helper != "":
		return {"program": helper, "args": args}
	var helper_script = _helper_script_path()
	if helper_script == "":
		return {}
	var python = _find_python()
	if python == "":
		return {}
	var script_args = PackedStringArray([helper_script])
	script_args.append_array(args)
	return {"program": python, "args": script_args}


func _helper_path() -> String:
	var helper_name = "pet_helper.exe" if OS.get_name() == "Windows" else "pet_helper"
	var candidates = [
		repo_root.path_join("scripts").path_join(helper_name),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join(helper_name),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _helper_script_path() -> String:
	var candidates = [
		repo_root.path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("scripts").path_join("pet_helper.py").simplify_path(),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _find_python() -> String:
	var override_path = OS.get_environment("PYTHON").strip_edges()
	if override_path != "":
		return override_path
	for candidate in ["python3", "python"]:
		var output := []
		var code = OS.execute(candidate, ["--version"], output, true, true)
		if code == 0:
			return candidate
	return ""
