extends Node

const HelperProcessLauncherScript = preload("res://scripts/HelperProcessLauncher.gd")

signal notify(message)

var repo_root := ""
var config_dir := ""
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
	if not helper_launcher.open_in_browser(args):
		var message := "找不到陪伴控制台 helper。" if helper_launcher.last_error == "not_found" else "陪伴控制台启动失败。"
		emit_signal("notify", message)
		return false
	emit_signal("notify", "已在浏览器打开陪伴控制台。")
	return true


func is_running() -> bool:
	return helper_launcher.is_running()


func stop() -> void:
	helper_launcher.stop()


func _exit_tree() -> void:
	stop()
