extends Window

signal skin_selected(skin_id)
signal notify(message)

const CACHOMON_PUBLIC_URL := "https://cachomon.com/list.php?a=0&g=1&m=0&t=1"

var skin_manager
var config_store
var repo_root := ""
var item_list: ItemList
var preview_rect: TextureRect
var title_label: Label
var quality_label: Label
var meta_label: Label
var coverage_label: Label
var license_label: Label
var action_list: ItemList
var report_text: TextEdit
var import_file_dialog: FileDialog
var import_folder_dialog: FileDialog
var delete_confirm: ConfirmationDialog
var pending_delete_skin_id := ""


func _ready() -> void:
	title = "皮肤管理"
	size = Vector2i(820, 560)
	min_size = Vector2i(700, 460)
	close_requested.connect(hide)
	_build_ui()


func configure(manager, store, root: String) -> void:
	skin_manager = manager
	config_store = store
	repo_root = root
	if skin_manager != null:
		skin_manager.skins_changed.connect(_refresh)


func open_window() -> void:
	_refresh()
	popup_centered()


func _build_ui() -> void:
	var root = HSplitContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(_on_item_selected)
	left.add_child(item_list)

	var buttons = HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	left.add_child(buttons)
	_add_button(buttons, "启用", _on_enable_pressed)
	_add_button(buttons, "导入 ZIP", _on_import_zip_pressed)
	_add_button(buttons, "导入文件夹", _on_import_folder_pressed)
	_add_button(buttons, "刷新", _refresh)
	_add_button(buttons, "删除", _on_delete_pressed)
	_add_button(buttons, "目录", _on_open_user_skins_pressed)
	_add_button(buttons, "Cachomon", _on_cachomon_pressed)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	right.add_child(header)

	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(112, 112)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(preview_rect)

	var header_text = VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	title_label = _make_label(22)
	header_text.add_child(title_label)
	quality_label = _make_label(16)
	header_text.add_child(quality_label)
	meta_label = _make_label(0)
	header_text.add_child(meta_label)

	coverage_label = _make_label(0)
	right.add_child(coverage_label)
	license_label = _make_label(0)
	right.add_child(license_label)

	action_list = ItemList.new()
	action_list.custom_minimum_size = Vector2(0, 150)
	action_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(action_list)

	report_text = TextEdit.new()
	report_text.custom_minimum_size = Vector2(0, 118)
	report_text.editable = false
	report_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right.add_child(report_text)

	import_file_dialog = FileDialog.new()
	import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_file_dialog.filters = PackedStringArray(["*.zip ; Shimeji ZIP"])
	import_file_dialog.file_selected.connect(_on_import_source_selected)
	add_child(import_file_dialog)

	import_folder_dialog = FileDialog.new()
	import_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	import_folder_dialog.dir_selected.connect(_on_import_source_selected)
	add_child(import_folder_dialog)

	delete_confirm = ConfirmationDialog.new()
	delete_confirm.title = "删除用户皮肤"
	delete_confirm.dialog_text = "确定要把这个用户皮肤移到回收站吗？"
	delete_confirm.confirmed.connect(_delete_selected_user_skin)
	add_child(delete_confirm)


func _make_label(font_size: int) -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _refresh() -> void:
	if item_list == null or skin_manager == null:
		return
	item_list.clear()
	var selected_id = skin_manager.selected_skin_id()
	var selected_index := -1
	var index := 0
	for skin in skin_manager.list_skins():
		var skin_id = str(skin.get("id", ""))
		var kind = str(skin.get("_kind", ""))
		var metadata = skin.get("metadata", {})
		var level = str(metadata.get("compatibility_level", "minimal")) if typeof(metadata) == TYPE_DICTIONARY else "minimal"
		var suffix = "  ✓" if skin_id == selected_id else ""
		item_list.add_item("%s [%s/%s]%s" % [str(skin.get("name", skin_id)), kind, level, suffix])
		item_list.set_item_metadata(index, skin_id)
		if skin_id == selected_id:
			selected_index = index
		index += 1
	if selected_index >= 0:
		item_list.select(selected_index)
		_update_detail(selected_index)
	elif item_list.item_count > 0:
		item_list.select(0)
		_update_detail(0)
	else:
		_clear_detail("没有可用皮肤。")


func _on_item_selected(index: int) -> void:
	_update_detail(index)


func _update_detail(index: int) -> void:
	if skin_manager == null or index < 0:
		return
	var skin_id = str(item_list.get_item_metadata(index))
	if not skin_manager.has_skin(skin_id):
		return
	var skin = skin_manager.skins_by_id[skin_id]
	var metadata: Dictionary = skin.get("metadata", {})
	var source: Dictionary = skin.get("source", {})
	var license: Dictionary = skin.get("license", {})
	title_label.text = str(skin.get("name", skin_id))
	quality_label.text = "兼容：%s  %d/100" % [
		str(metadata.get("compatibility_level", "minimal")),
		int(metadata.get("compatibility_score", 0)),
	]
	meta_label.text = "ID: %s\n类型: %s  版本: %s  作者: %s\n来源: %s %s" % [
		skin_id,
		str(skin.get("_kind", "")),
		str(metadata.get("package_version", "1.0.0")),
		_format_authors(metadata.get("authors", [])),
		str(source.get("format", "skin-json")),
		str(source.get("image_set", "")),
	]
	coverage_label.text = "能力覆盖：%s" % _format_coverage(metadata.get("capability_coverage", {}))
	license_label.text = "授权：%s；可再分发：%s\n%s" % [
		str(license.get("type", "unknown")),
		"是" if bool(license.get("redistributable", false)) else "否",
		str(license.get("summary", "")),
	]
	_load_preview(skin)
	_fill_action_list(skin)
	report_text.text = _format_report(skin)


func _clear_detail(message: String) -> void:
	preview_rect.texture = null
	title_label.text = message
	quality_label.text = ""
	meta_label.text = ""
	coverage_label.text = ""
	license_label.text = ""
	action_list.clear()
	report_text.text = ""


func _selected_skin_id() -> String:
	if item_list == null:
		return ""
	var selected = item_list.get_selected_items()
	if selected.is_empty():
		return ""
	return str(item_list.get_item_metadata(int(selected[0])))


func _on_enable_pressed() -> void:
	var skin_id = _selected_skin_id()
	if skin_id != "":
		emit_signal("skin_selected", skin_id)


func _on_import_zip_pressed() -> void:
	import_file_dialog.popup_centered(Vector2i(720, 460))


func _on_import_folder_pressed() -> void:
	import_folder_dialog.popup_centered(Vector2i(720, 460))


func _on_import_source_selected(path: String) -> void:
	if skin_manager == null:
		return
	DirAccess.make_dir_recursive_absolute(skin_manager.user_skin_root)
	var output := []
	var code = _run_importer(path, output)
	if code == 0:
		skin_manager.reload_skins()
		_refresh()
		var message = _import_summary(output)
		emit_signal("notify", message)
	else:
		var text = "\n".join(output)
		report_text.text = text
		emit_signal("notify", "导入失败：%s" % text.left(180))


func _on_delete_pressed() -> void:
	var skin_id = _selected_skin_id()
	if skin_id == "" or skin_manager == null or not skin_manager.has_skin(skin_id):
		return
	var skin = skin_manager.skins_by_id[skin_id]
	if str(skin.get("_kind", "")) != "user":
		emit_signal("notify", "只能删除用户导入的皮肤。")
		return
	pending_delete_skin_id = skin_id
	delete_confirm.dialog_text = "确定要把“%s”移到回收站吗？" % str(skin.get("name", skin_id))
	delete_confirm.popup_centered()


func _delete_selected_user_skin() -> void:
	if pending_delete_skin_id == "":
		return
	if skin_manager.delete_user_skin(pending_delete_skin_id):
		pending_delete_skin_id = ""
		_refresh()
		emit_signal("notify", "用户皮肤已移到回收站。")
	else:
		emit_signal("notify", "删除失败。")


func _on_open_user_skins_pressed() -> void:
	if skin_manager == null:
		return
	DirAccess.make_dir_recursive_absolute(skin_manager.user_skin_root)
	OS.shell_open(skin_manager.user_skin_root)


func _on_cachomon_pressed() -> void:
	OS.shell_open(CACHOMON_PUBLIC_URL)


func _fill_action_list(skin: Dictionary) -> void:
	action_list.clear()
	var actions: Dictionary = skin.get("actions", {})
	var tags = _action_tags(skin)
	for action_id in actions.keys():
		var action: Dictionary = actions[action_id]
		var frames = action.get("frames", [])
		var frame_count = frames.size() if typeof(frames) == TYPE_ARRAY else 0
		var flags := []
		if bool(action.get("mirror_x", false)):
			flags.append("mirror")
		if bool(action.get("native_edge_pose", false)):
			flags.append("edge-pose")
		var tag_text = ", ".join(tags.get(action_id, []))
		var flag_text = "" if flags.is_empty() else "  [%s]" % ", ".join(flags)
		action_list.add_item("%s  %s  %d frames%s" % [
			str(action.get("name", action_id)),
			tag_text,
			frame_count,
			flag_text,
		])


func _action_tags(skin: Dictionary) -> Dictionary:
	var result := {}
	var capabilities: Dictionary = skin.get("capabilities", {})
	for capability in capabilities.keys():
		var candidates = capabilities[capability]
		if typeof(candidates) != TYPE_ARRAY:
			continue
		for candidate in candidates:
			if typeof(candidate) != TYPE_DICTIONARY:
				continue
			var action_id = str(candidate.get("action", ""))
			if action_id == "":
				continue
			if not result.has(action_id):
				result[action_id] = []
			var label = str(capability)
			var direction = str(candidate.get("direction", ""))
			if direction != "":
				label += ":%s" % direction
			result[action_id].append(label)
	return result


func _format_report(skin: Dictionary) -> String:
	var report: Dictionary = skin.get("import_report", {})
	if report.is_empty():
		return "没有导入报告。"
	var parts := [
		"导入报告",
		"动作 %d，帧 %d，兼容 %s %d/100" % [
			int(report.get("action_count", 0)),
			int(report.get("frame_count", 0)),
			str(report.get("compatibility_level", "minimal")),
			int(report.get("compatibility_score", 0)),
		],
	]
	var mirrors = report.get("generated_mirrors", [])
	if typeof(mirrors) == TYPE_ARRAY and not mirrors.is_empty():
		parts.append("镜像动作：%s" % ", ".join(mirrors))
	var failed = report.get("failed_frames", [])
	if typeof(failed) == TYPE_ARRAY and not failed.is_empty():
		parts.append("失败帧：%s" % ", ".join(failed).left(220))
	var warnings = report.get("warnings", [])
	if typeof(warnings) == TYPE_ARRAY and not warnings.is_empty():
		parts.append("警告：%s" % "\n".join(warnings).left(500))
	var errors = report.get("errors", [])
	if typeof(errors) == TYPE_ARRAY and not errors.is_empty():
		parts.append("错误：%s" % "\n".join(errors).left(500))
	return "\n".join(parts)


func _import_summary(output: Array) -> String:
	var parsed = JSON.parse_string("\n".join(output))
	if typeof(parsed) != TYPE_ARRAY:
		return "皮肤导入完成。"
	if parsed.is_empty():
		return "皮肤导入完成。"
	var report = parsed[0].get("report", {}) if typeof(parsed[0]) == TYPE_DICTIONARY else {}
	if typeof(report) != TYPE_DICTIONARY:
		return "皮肤导入完成。"
	return "皮肤导入完成：%s %d/100。" % [
		str(report.get("compatibility_level", "minimal")),
		int(report.get("compatibility_score", 0)),
	]


func _format_coverage(coverage) -> String:
	if typeof(coverage) != TYPE_DICTIONARY:
		return "未知"
	var labels := []
	for capability in ["resting", "locomotion", "falling", "held", "edge"]:
		labels.append("%s=%s" % [capability, "ok" if bool(coverage.get(capability, false)) else "missing"])
	return "  ".join(labels)


func _format_authors(authors) -> String:
	if typeof(authors) != TYPE_ARRAY or authors.is_empty():
		return "未知"
	var names := []
	for author in authors:
		if typeof(author) == TYPE_DICTIONARY:
			names.append(str(author.get("name", "unknown")))
		else:
			names.append(str(author))
	return ", ".join(names)


func _load_preview(skin: Dictionary) -> void:
	preview_rect.texture = null
	var preview = str(skin.get("preview", ""))
	var frame_root = str(skin.get("_frame_root_abs", ""))
	if preview == "" or frame_root == "":
		return
	var path = frame_root.path_join(preview)
	if not FileAccess.file_exists(path):
		return
	var image = Image.new()
	if image.load(path) == OK:
		preview_rect.texture = ImageTexture.create_from_image(image)


func _importer_script_path() -> String:
	var candidates = [
		repo_root.path_join("scripts").path_join("import_shimeji_skin.py"),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join("import_shimeji_skin.py"),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _run_importer(source_path: String, output: Array) -> int:
	var args = [
		"import-shimeji",
		source_path,
		"--output-root",
		skin_manager.user_skin_root,
		"--json-report",
	]
	var helper = _helper_path()
	if helper != "":
		return OS.execute(helper, args, output, true, true)
	var script_path = _importer_script_path()
	if script_path == "":
		output.append("import_shimeji_skin.py not found")
		return 2
	var python = _find_python()
	if python == "":
		output.append("Python not found")
		return 2
	return OS.execute(python, [
		script_path,
		source_path,
		"--output-root",
		skin_manager.user_skin_root,
		"--json-report",
	], output, true, true)


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


func _find_python() -> String:
	for candidate in ["python3", "python"]:
		var output := []
		var code = OS.execute(candidate, ["--version"], output, true, true)
		if code == 0:
			return candidate
	return ""
