extends RefCounted

var repo_root := ""
var helper_pid := -1
var last_error := ""


func configure(root: String) -> void:
	repo_root = root


func launch(args: PackedStringArray) -> int:
	last_error = ""
	var command = _helper_command(args)
	if command.is_empty():
		helper_pid = -1
		last_error = "not_found"
		return -1
	var process_args: PackedStringArray = command["args"]
	helper_pid = OS.create_process(str(command["program"]), process_args, false)
	if helper_pid <= 0:
		last_error = "start_failed"
	return helper_pid


func stop() -> void:
	if helper_pid > 0:
		OS.kill(helper_pid)
		helper_pid = -1


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
	for candidate in ["python3", "python"]:
		var output := []
		var code = OS.execute(candidate, ["--version"], output, true, true)
		if code == 0:
			return candidate
	return ""
