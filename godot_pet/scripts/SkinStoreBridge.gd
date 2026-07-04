extends Node

signal skin_requested(skin_id)
signal notify(message)

var repo_root := ""
var config_dir := ""
var command_path := ""
var helper_pid := -1
var handled_nonce := ""
var poll_timer: Timer


func configure(root: String, user_config_dir: String) -> void:
	repo_root = root
	config_dir = user_config_dir
	command_path = config_dir.path_join("skin_store_command.json")
	if poll_timer == null:
		poll_timer = Timer.new()
		poll_timer.wait_time = 0.5
		poll_timer.timeout.connect(_poll_command)
		add_child(poll_timer)
	poll_timer.start()


func open_store() -> bool:
	var args = PackedStringArray([
		"skin-store",
		"--repo-root",
		repo_root,
		"--config-dir",
		config_dir,
		"--open-browser",
		"--idle-timeout",
		"900",
	])
	var command = _helper_command(args)
	if command.is_empty():
		emit_signal("notify", "找不到皮肤商店 helper。")
		return false
	var process_args: PackedStringArray = command["args"]
	helper_pid = OS.create_process(str(command["program"]), process_args, false)
	if helper_pid <= 0:
		emit_signal("notify", "皮肤商店启动失败。")
		return false
	emit_signal("notify", "已在浏览器打开皮肤商店。")
	return true


func stop() -> void:
	if helper_pid > 0:
		OS.kill(helper_pid)
		helper_pid = -1


func _poll_command() -> void:
	if command_path == "" or not FileAccess.file_exists(command_path):
		return
	var file = FileAccess.open(command_path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file = null
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var nonce = str(parsed.get("nonce", ""))
	if nonce != "" and nonce == handled_nonce:
		return
	handled_nonce = nonce
	if str(parsed.get("command", "")) == "select_skin":
		var skin_id = str(parsed.get("skin_id", "")).strip_edges()
		if skin_id != "":
			DirAccess.remove_absolute(command_path)
			emit_signal("skin_requested", skin_id)


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
