extends Node

signal notify(text)

const PinImageWindowScript = preload("res://scripts/PinImageWindow.gd")
const SettingsWindowScript = preload("res://scripts/ScreenshotSettingsWindow.gd")
const SelectionWindowScript = preload("res://scripts/ScreenshotSelectionWindow.gd")

const CONFIG_DIR_NAME := "mascotmate-desktop"
const HOTKEY_PORT := 38291
const MAX_HISTORY := 3
const DEFAULT_CONFIG := {
	"shortcuts": {
		"screenshot": "F1",
		"paste_pin": "F3",
		"close_pin": "F4",
	},
	"screenshot": {
		"backend": "auto",
	},
	"pins": {
		"max_count": 3,
	},
}

var repo_root := ""
var config := DEFAULT_CONFIG.duplicate(true)
var config_dir := ""
var screenshot_dir := ""
var config_path := ""
var history := []
var pins := []
var active_pin: Window
var paste_cursor := 0
var udp: PacketPeerUDP
var udp_bound := false
var hotkey_pid := -1
var settings_window
var screenshot_active := false
var config_store


func configure(root: String, store = null) -> void:
	repo_root = root
	config_store = store
	config_dir = str(config_store.config_dir) if config_store != null else _config_dir()
	screenshot_dir = config_dir.path_join("screenshots")
	config_path = config_dir.path_join("config.json")
	if config_store != null:
		config = _merged_config(config_store.get_config())
	else:
		_load_config()
	_load_history()
	_start_udp()
	_start_hotkey_helper()


func _process(_delta: float) -> void:
	_poll_udp()


func _exit_tree() -> void:
	_stop_hotkey_helper()
	if udp != null:
		udp.close()
	udp_bound = false


func handle_input(event: InputEvent) -> bool:
	if settings_window != null and is_instance_valid(settings_window) and settings_window.visible:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var shortcut = _shortcut_from_event(event)
		if shortcut == str(config["shortcuts"].get("screenshot", "F1")):
			take_screenshot()
			return true
		if shortcut == str(config["shortcuts"].get("paste_pin", "F3")):
			paste_next_pin()
			return true
		if shortcut == str(config["shortcuts"].get("close_pin", "F4")):
			close_active_pin()
			return true
	return false


func open_settings() -> void:
	if settings_window == null or not is_instance_valid(settings_window):
		settings_window = SettingsWindowScript.new()
		settings_window.settings_saved.connect(_on_settings_saved)
		settings_window.settings_closed.connect(_on_settings_closed)
		add_child(settings_window)
	_stop_hotkey_helper()
	settings_window.open_with_config(config)


func take_screenshot() -> void:
	if screenshot_active:
		return
	screenshot_active = true
	var output_path = screenshot_dir.path_join(_screenshot_file_name())
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var hidden_windows = _hide_windows_for_screenshot()
	await get_tree().create_timer(0.16).timeout
	var result = await _run_screenshot_flow(output_path)
	_restore_windows_after_screenshot(hidden_windows)
	screenshot_active = false
	if bool(result.get("saved", false)) and FileAccess.file_exists(output_path):
		_add_history(output_path)
		if bool(result.get("copied", false)):
			emit_signal("notify", "截图已保存并复制到剪贴板。")
		else:
			emit_signal("notify", "截图已保存；复制到剪贴板失败。")
	else:
		emit_signal("notify", str(result.get("message", "截图取消或失败。")))


func paste_next_pin() -> void:
	_prune_pins()
	var max_count = _max_pin_count()
	if pins.size() >= max_count:
		emit_signal("notify", "最多只能贴 %d 张图。" % max_count)
		return

	if history.is_empty():
		if _paste_clipboard_image():
			return
		emit_signal("notify", "剪贴板里没有图片。")
		return

	var attempts = min(history.size(), MAX_HISTORY)
	var selected_path = ""
	for _i in range(attempts):
		var candidate = str(history[paste_cursor % attempts])
		paste_cursor = (paste_cursor + 1) % attempts
		if FileAccess.file_exists(candidate):
			selected_path = candidate
			break
	if selected_path == "":
		_load_history()
		emit_signal("notify", "没有可贴的截图。")
		return
	_pin_image_path(selected_path)


func close_active_pin() -> void:
	_prune_pins()
	var target = active_pin
	if target == null or not is_instance_valid(target):
		target = pins[pins.size() - 1] if not pins.is_empty() else null
	if target == null:
		emit_signal("notify", "当前没有贴图。")
		return
	pins.erase(target)
	if target == active_pin:
		active_pin = null
	target.queue_free()
	if active_pin == null and not pins.is_empty():
		active_pin = pins[pins.size() - 1]


func set_pins_visible(value: bool) -> void:
	_prune_pins()
	for pin in pins:
		pin.visible = value


func _on_settings_saved(next_config: Dictionary) -> void:
	config = _merged_config(next_config)
	if config_store != null:
		config_store.set_screenshot_pins_config(config)
		config = _merged_config(config_store.get_config())
	else:
		_save_config()
	_trim_pins_to_limit()
	_restart_hotkey_helper()
	emit_signal("notify", "截图贴图设置已保存。")


func _on_settings_closed() -> void:
	if hotkey_pid <= 0 and udp_bound:
		_start_hotkey_helper()


func _start_udp() -> void:
	udp = PacketPeerUDP.new()
	var err = udp.bind(HOTKEY_PORT, "127.0.0.1")
	if err != OK:
		udp.close()
		udp = null
		udp_bound = false
		emit_signal("notify", "全局快捷键端口不可用，保留应用内快捷键。")
		return
	udp_bound = true


func _poll_udp() -> void:
	if udp == null:
		return
	while udp.get_available_packet_count() > 0:
		var packet = udp.get_packet()
		var command = packet.get_string_from_utf8().strip_edges()
		match command:
			"screenshot":
				take_screenshot()
			"paste_pin":
				paste_next_pin()
			"close_pin":
				close_active_pin()


func _start_hotkey_helper() -> void:
	if not udp_bound:
		return
	if not _global_hotkeys_enabled():
		return
	var command = _helper_command(PackedStringArray([
		"hotkeys",
		"--port",
		str(HOTKEY_PORT),
		"--screenshot",
		str(config["shortcuts"].get("screenshot", "F1")),
		"--paste-pin",
		str(config["shortcuts"].get("paste_pin", "F3")),
		"--close-pin",
		str(config["shortcuts"].get("close_pin", "F4")),
	]))
	if command.is_empty():
		emit_signal("notify", "未找到跨平台辅助程序，保留应用内快捷键。")
		return
	var args: PackedStringArray = command["args"]
	hotkey_pid = OS.create_process(str(command["program"]), args, false)
	if hotkey_pid <= 0:
		emit_signal("notify", "全局快捷键启动失败，保留应用内快捷键。")


func _stop_hotkey_helper() -> void:
	if hotkey_pid > 0:
		OS.kill(hotkey_pid)
		hotkey_pid = -1


func _restart_hotkey_helper() -> void:
	_stop_hotkey_helper()
	_start_hotkey_helper()


func _global_hotkeys_enabled() -> bool:
	if OS.get_environment("CRAYON_PET_ENABLE_GLOBAL_HOTKEYS").strip_edges() in ["0", "false", "False"]:
		return false
	if OS.get_name() == "Linux":
		var session = OS.get_environment("XDG_SESSION_TYPE").to_lower()
		var display = OS.get_environment("DISPLAY")
		var wayland = OS.get_environment("WAYLAND_DISPLAY")
		if display == "" or (session == "wayland" and wayland != ""):
			emit_signal("notify", "Wayland 下暂不启用全局快捷键。")
			return false
	if OS.get_name() == "Web":
		return false
	if OS.get_name() == "macOS" and OS.get_environment("CRAYON_PET_ENABLE_GLOBAL_HOTKEYS").strip_edges() == "":
		emit_signal("notify", "macOS 首次使用全局快捷键可能需要授予辅助功能权限。")
	return true


func _run_screenshot_flow(output_path: String) -> Dictionary:
	var backend = str(config["screenshot"].get("backend", "auto"))
	if backend in ["auto", "godot"]:
		var godot_result = await _run_godot_screenshot(output_path)
		if bool(godot_result.get("saved", false)) or backend == "godot" or not bool(godot_result.get("fallback", false)):
			return godot_result
	if backend in ["auto", "spectacle", "import"]:
		return _run_legacy_screenshot_command(output_path)
	return {
		"saved": false,
		"copied": false,
		"message": "截图后端配置不可用。"
	}


func _run_godot_screenshot(output_path: String) -> Dictionary:
	var screen = _mouse_screen()
	var image = DisplayServer.screen_get_image(screen)
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return {
			"saved": false,
			"copied": false,
			"fallback": true,
			"message": "Godot 截图不可用，正在尝试系统截图工具。"
		}

	var screen_rect = Rect2i(
		DisplayServer.screen_get_position(screen),
		DisplayServer.screen_get_size(screen)
	)
	var crop = await _select_screenshot_region(image, screen_rect)
	if crop == null:
		return {
			"saved": false,
			"copied": false,
			"fallback": false,
			"message": "截图已取消。"
		}
	if crop.save_png(output_path) != OK:
		return {
			"saved": false,
			"copied": false,
			"fallback": false,
			"message": "截图保存失败。"
		}
	return {
		"saved": true,
		"copied": _copy_image_to_clipboard(output_path),
		"fallback": false,
		"message": ""
	}


func _select_screenshot_region(image: Image, screen_rect: Rect2i):
	var selector = SelectionWindowScript.new()
	add_child(selector)
	selector.open_with_capture(image, screen_rect)
	var result = await selector.selection_finished
	if is_instance_valid(selector):
		selector.queue_free()
	if result.size() < 2 or not bool(result[0]):
		return null
	return result[1]


func _mouse_screen() -> int:
	var mouse = DisplayServer.mouse_get_position()
	var screen = DisplayServer.get_screen_from_rect(Rect2i(mouse, Vector2i(1, 1)))
	if screen < 0:
		screen = DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	return screen


func _run_legacy_screenshot_command(output_path: String) -> Dictionary:
	if OS.get_name() != "Linux":
		return {
			"saved": false,
			"copied": false,
			"message": "当前平台不支持旧截图工具。"
		}
	var backend = str(config["screenshot"].get("backend", "auto"))
	var spectacle_path = _command_path("spectacle")
	if backend in ["auto", "spectacle"] and spectacle_path != "":
		var code = OS.execute(spectacle_path, PackedStringArray([
			"--region",
			"--background",
			"--nonotify",
			"--copy-image",
			"--output",
			output_path,
		]), [], true)
		return {
			"saved": code == 0,
			"copied": code == 0,
			"message": "" if code == 0 else "Spectacle 截图取消或失败。"
		}
	var import_path = _command_path("import")
	if backend in ["auto", "import"] and import_path != "":
		var code = OS.execute(import_path, PackedStringArray([output_path]), [], true)
		return {
			"saved": code == 0,
			"copied": code == 0 and _copy_image_to_clipboard(output_path),
			"message": "" if code == 0 else "ImageMagick 截图取消或失败。"
		}
	return {
		"saved": false,
		"copied": false,
		"message": "未找到可用截图工具。"
	}


func _copy_image_to_clipboard(path: String) -> bool:
	var command = _helper_command(PackedStringArray(["copy-image", path]))
	if command.is_empty():
		return false
	var output := []
	var args: PackedStringArray = command["args"]
	var code = OS.execute(str(command["program"]), args, output, true)
	return code == 0


func _paste_clipboard_image() -> bool:
	if not DisplayServer.clipboard_has_image():
		return false
	var image = DisplayServer.clipboard_get_image()
	if image == null or image.get_width() <= 0:
		return false
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var path = screenshot_dir.path_join(_screenshot_file_name("clipboard"))
	if image.save_png(path) == OK:
		_add_history(path)
		return _pin_image(image, path)
	return _pin_image(image, "")


func _pin_image_path(path: String) -> bool:
	var image = Image.new()
	if image.load(path) != OK:
		emit_signal("notify", "图片读取失败。")
		return false
	return _pin_image(image, path)


func _pin_image(image: Image, path: String) -> bool:
	var pin = PinImageWindowScript.new()
	var mouse = DisplayServer.mouse_get_position()
	var max_size = _pin_max_size()
	var start_position = Vector2i(mouse.x + 18, mouse.y + 18)
	if not pin.setup(image, path, start_position, max_size):
		pin.queue_free()
		return false
	pin.activated.connect(_on_pin_activated)
	pin.close_requested.connect(func(): _on_pin_closed(pin))
	pin.tree_exiting.connect(func(): _on_pin_closed(pin))
	add_child(pin)
	pin.visible = true
	pins.append(pin)
	active_pin = pin
	return true


func _on_pin_activated(pin: Window) -> void:
	if is_instance_valid(pin):
		active_pin = pin


func _on_pin_closed(pin: Window) -> void:
	pins.erase(pin)
	if active_pin == pin:
		active_pin = pins[pins.size() - 1] if not pins.is_empty() else null


func _hide_windows_for_screenshot() -> Array:
	var hidden := []
	var main_window = get_window()
	if main_window.visible:
		hidden.append(main_window)
		main_window.visible = false
	for pin in pins:
		if is_instance_valid(pin) and pin.visible:
			hidden.append(pin)
			pin.visible = false
	return hidden


func _restore_windows_after_screenshot(hidden_windows: Array) -> void:
	for window in hidden_windows:
		if is_instance_valid(window):
			window.visible = true


func _add_history(path: String) -> void:
	history.erase(path)
	history.push_front(path)
	while history.size() > MAX_HISTORY:
		var old_path = str(history.pop_back())
		if FileAccess.file_exists(old_path):
			DirAccess.remove_absolute(old_path)
	paste_cursor = 0


func _load_history() -> void:
	history.clear()
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	var dir = DirAccess.open(screenshot_dir)
	if dir == null:
		return
	var files := []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".png"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	files.reverse()
	for file in files:
		history.append(screenshot_dir.path_join(file))
		if history.size() >= MAX_HISTORY:
			break


func _load_config() -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				config = _merged_config(parsed)
	_save_config()


func _save_config() -> void:
	DirAccess.make_dir_recursive_absolute(config_dir)
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(config, "\t"))


func _merged_config(source: Dictionary) -> Dictionary:
	var merged = DEFAULT_CONFIG.duplicate(true)
	if source.has("shortcuts") and typeof(source["shortcuts"]) == TYPE_DICTIONARY:
		for key in merged["shortcuts"].keys():
			if source["shortcuts"].has(key):
				merged["shortcuts"][key] = str(source["shortcuts"][key])
	if source.has("screenshot") and typeof(source["screenshot"]) == TYPE_DICTIONARY:
		if source["screenshot"].has("backend"):
			var backend = str(source["screenshot"]["backend"])
			merged["screenshot"]["backend"] = backend if backend in ["auto", "godot", "spectacle", "import"] else "auto"
	if source.has("pins") and typeof(source["pins"]) == TYPE_DICTIONARY:
		if source["pins"].has("max_count"):
			merged["pins"]["max_count"] = clampi(int(source["pins"]["max_count"]), 1, 3)
	return merged


func _prune_pins() -> void:
	var alive := []
	for pin in pins:
		if is_instance_valid(pin):
			alive.append(pin)
	pins = alive
	if active_pin != null and not is_instance_valid(active_pin):
		active_pin = null


func _trim_pins_to_limit() -> void:
	_prune_pins()
	while pins.size() > _max_pin_count():
		var pin = pins.pop_front()
		if active_pin == pin:
			active_pin = null
		if is_instance_valid(pin):
			pin.queue_free()
	if active_pin == null and not pins.is_empty():
		active_pin = pins[pins.size() - 1]


func _max_pin_count() -> int:
	return clampi(int(config["pins"].get("max_count", 3)), 1, 3)


func _pin_max_size() -> Vector2i:
	var screen = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen)
	return Vector2i(max(120, int(screen_size.x * 0.82)), max(120, int(screen_size.y * 0.82)))


func _screenshot_file_name(prefix := "screenshot") -> String:
	var stamp = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	return "%s_%s_%d.png" % [prefix, stamp, Time.get_ticks_msec()]


func _config_dir() -> String:
	if OS.get_name() in ["Windows", "macOS"]:
		return ProjectSettings.globalize_path("user://")
	var home = OS.get_environment("HOME")
	if home == "":
		return ProjectSettings.globalize_path("user://")
	return home.path_join(".config").path_join(CONFIG_DIR_NAME)


func _helper_command(args: PackedStringArray) -> Dictionary:
	var executable = _helper_executable_path()
	if executable != "":
		return {
			"program": executable,
			"args": args,
		}
	var script_path = _helper_script_path()
	var python_path = _find_python()
	if script_path != "" and python_path != "":
		var script_args = PackedStringArray([script_path])
		script_args.append_array(args)
		return {
			"program": python_path,
			"args": script_args,
		}
	return {}


func _helper_executable_path() -> String:
	var exe_name = "pet_helper.exe" if OS.get_name() == "Windows" else "pet_helper"
	var candidates = [
		repo_root.path_join("scripts").path_join(exe_name),
		ProjectSettings.globalize_path("res://..").path_join("scripts").path_join(exe_name),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join(exe_name),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("scripts").path_join(exe_name).simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").path_join("scripts").path_join(exe_name).simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").path_join("..").path_join("scripts").path_join(exe_name).simplify_path(),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _helper_script_path() -> String:
	var candidates = [
		repo_root.path_join("scripts").path_join("pet_helper.py"),
		ProjectSettings.globalize_path("res://..").path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("scripts").path_join("pet_helper.py").simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").path_join("scripts").path_join("pet_helper.py").simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").path_join("..").path_join("scripts").path_join("pet_helper.py").simplify_path(),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _find_python() -> String:
	var env = OS.get_environment("PYTHON")
	if env != "":
		return env
	var python3 = _command_path("python3")
	if python3 != "":
		return python3
	return _command_path("python")


func _command_path(command: String) -> String:
	var output := []
	var code = 1
	if OS.get_name() == "Windows":
		code = OS.execute("cmd", PackedStringArray(["/C", "where", command]), output, true)
	else:
		code = OS.execute("sh", PackedStringArray(["-lc", "command -v %s" % command]), output, true)
	if code != 0 or output.is_empty():
		return ""
	return str(output[0]).strip_edges().split("\n")[0].strip_edges()


func _shortcut_from_event(event: InputEventKey) -> String:
	var base = _key_name(event)
	if base == "":
		return ""
	var parts := []
	if event.ctrl_pressed:
		parts.append("Ctrl")
	if event.alt_pressed:
		parts.append("Alt")
	if event.shift_pressed:
		parts.append("Shift")
	if event.meta_pressed:
		parts.append("Super")
	parts.append(base)
	return "+".join(parts)


func _key_name(event: InputEventKey) -> String:
	var code = event.keycode
	if code == 0:
		code = event.physical_keycode
	match code:
		KEY_F1:
			return "F1"
		KEY_F2:
			return "F2"
		KEY_F3:
			return "F3"
		KEY_F4:
			return "F4"
		KEY_F5:
			return "F5"
		KEY_F6:
			return "F6"
		KEY_F7:
			return "F7"
		KEY_F8:
			return "F8"
		KEY_F9:
			return "F9"
		KEY_F10:
			return "F10"
		KEY_F11:
			return "F11"
		KEY_F12:
			return "F12"
		KEY_SPACE:
			return "Space"
		KEY_ESCAPE:
			return "Escape"
		KEY_ENTER:
			return "Enter"
		KEY_TAB:
			return "Tab"
		_:
			if code >= KEY_A and code <= KEY_Z:
				return char(code)
			if code >= KEY_0 and code <= KEY_9:
				return char(code)
			return OS.get_keycode_string(code)
