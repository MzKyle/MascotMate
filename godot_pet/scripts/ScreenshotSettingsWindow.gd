extends Window

signal settings_saved(config)
signal settings_closed

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

var working_config := {}
var capture_target := ""
var shortcut_buttons := {}
var max_pins_spin: SpinBox
var status_label: Label


func _ready() -> void:
	title = "截图贴图设置"
	size = Vector2i(540, 360)
	min_size = Vector2i(500, 320)
	always_on_top = true
	unresizable = false
	_build_ui()


func open_with_config(config: Dictionary) -> void:
	working_config = _merged_config(config)
	_apply_to_controls()
	popup_centered()
	grab_focus()


func _input(event: InputEvent) -> void:
	if capture_target == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var shortcut = _shortcut_from_event(event)
		if shortcut == "":
			return
		working_config["shortcuts"][capture_target] = shortcut
		capture_target = ""
		_update_shortcut_buttons()
		_set_status("已记录快捷键。")
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_without_save()


func _build_ui() -> void:
	var root = MarginContainer.new()
	root.add_theme_constant_override("margin_left", 18)
	root.add_theme_constant_override("margin_right", 18)
	root.add_theme_constant_override("margin_top", 16)
	root.add_theme_constant_override("margin_bottom", 16)
	add_child(root)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	root.add_child(box)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	_add_shortcut_row(grid, "截图", "screenshot")
	_add_shortcut_row(grid, "贴图", "paste_pin")
	_add_shortcut_row(grid, "关闭贴图", "close_pin")

	var max_label = Label.new()
	max_label.text = "最大贴图数"
	grid.add_child(max_label)

	max_pins_spin = SpinBox.new()
	max_pins_spin.min_value = 1
	max_pins_spin.max_value = 3
	max_pins_spin.step = 1
	max_pins_spin.value_changed.connect(_on_max_pins_changed)
	grid.add_child(max_pins_spin)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	var defaults_button = Button.new()
	defaults_button.text = "恢复默认"
	defaults_button.pressed.connect(_on_restore_defaults)
	buttons.add_child(defaults_button)

	var save_button = Button.new()
	save_button.text = "保存"
	save_button.pressed.connect(_on_save)
	buttons.add_child(save_button)

	var close_button = Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_close_without_save)
	buttons.add_child(close_button)


func _add_shortcut_row(parent: GridContainer, label_text: String, key: String) -> void:
	var label = Label.new()
	label.text = label_text
	parent.add_child(label)

	var button = Button.new()
	button.custom_minimum_size = Vector2(180, 32)
	button.pressed.connect(func(): _begin_capture(key))
	parent.add_child(button)
	shortcut_buttons[key] = button


func _begin_capture(key: String) -> void:
	capture_target = key
	_update_shortcut_buttons()
	_set_status("按下新的快捷键。")


func _on_max_pins_changed(value: float) -> void:
	working_config["pins"]["max_count"] = clampi(roundi(value), 1, 3)


func _on_restore_defaults() -> void:
	working_config = DEFAULT_CONFIG.duplicate(true)
	_apply_to_controls()
	_set_status("已恢复默认值，保存后生效。")


func _on_save() -> void:
	capture_target = ""
	working_config["pins"]["max_count"] = clampi(int(working_config["pins"].get("max_count", 3)), 1, 3)
	emit_signal("settings_saved", working_config.duplicate(true))
	hide()


func _close_without_save() -> void:
	capture_target = ""
	hide()
	emit_signal("settings_closed")


func _apply_to_controls() -> void:
	_update_shortcut_buttons()
	max_pins_spin.value = clampi(int(working_config["pins"].get("max_count", 3)), 1, 3)
	_set_status("")


func _update_shortcut_buttons() -> void:
	for key in shortcut_buttons.keys():
		var button: Button = shortcut_buttons[key]
		if key == capture_target:
			button.text = "正在录制..."
		else:
			button.text = str(working_config["shortcuts"].get(key, ""))


func _set_status(text: String) -> void:
	status_label.text = text


func _merged_config(config: Dictionary) -> Dictionary:
	var merged = DEFAULT_CONFIG.duplicate(true)
	if config.has("shortcuts") and typeof(config["shortcuts"]) == TYPE_DICTIONARY:
		for key in merged["shortcuts"].keys():
			if config["shortcuts"].has(key):
				merged["shortcuts"][key] = str(config["shortcuts"][key])
	if config.has("screenshot") and typeof(config["screenshot"]) == TYPE_DICTIONARY:
		if config["screenshot"].has("backend"):
			var backend = str(config["screenshot"]["backend"])
			merged["screenshot"]["backend"] = backend if backend in ["auto", "godot", "spectacle", "import"] else "auto"
	if config.has("pins") and typeof(config["pins"]) == TYPE_DICTIONARY:
		if config["pins"].has("max_count"):
			merged["pins"]["max_count"] = clampi(int(config["pins"]["max_count"]), 1, 3)
	return merged


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
