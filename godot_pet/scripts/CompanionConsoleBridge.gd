extends Node

const HelperProcessLauncherScript = preload("res://scripts/HelperProcessLauncher.gd")

signal command_received(command)
signal notify(message)

var repo_root := ""
var config_dir := ""
var command_path := ""
var helper_pid := -1
var handled_nonce := ""
var poll_timer: Timer
var helper_launcher = HelperProcessLauncherScript.new()


func configure(root: String, user_config_dir: String) -> void:
	repo_root = root
	config_dir = user_config_dir
	command_path = config_dir.path_join("companion_console_command.json")
	helper_launcher.configure(repo_root)
	if poll_timer == null:
		poll_timer = Timer.new()
		poll_timer.wait_time = 0.35
		poll_timer.timeout.connect(_poll_command)
		add_child(poll_timer)
	poll_timer.start()


func open_console() -> bool:
	var args = PackedStringArray([
		"companion-console",
		"--repo-root",
		repo_root,
		"--config-dir",
		config_dir,
		"--open-browser",
		"--idle-timeout",
		"900",
	])
	helper_pid = helper_launcher.launch(args)
	if helper_pid <= 0 and helper_launcher.last_error == "not_found":
		emit_signal("notify", "找不到陪伴控制台 helper。")
		return false
	if helper_pid <= 0:
		emit_signal("notify", "陪伴控制台启动失败。")
		return false
	emit_signal("notify", "已在浏览器打开陪伴控制台。")
	return true


func stop() -> void:
	helper_launcher.stop()
	helper_pid = helper_launcher.helper_pid


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
	DirAccess.remove_absolute(command_path)
	emit_signal("command_received", parsed.duplicate(true))
