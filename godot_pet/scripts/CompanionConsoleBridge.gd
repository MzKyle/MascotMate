extends Node

const HelperProcessLauncherScript = preload("res://scripts/HelperProcessLauncher.gd")

signal notify(message)

var repo_root := ""
var config_dir := ""
var helper_pid := -1
var helper_launcher = HelperProcessLauncherScript.new()


func configure(root: String, user_config_dir: String) -> void:
	repo_root = root
	config_dir = user_config_dir
	helper_launcher.configure(repo_root)


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
