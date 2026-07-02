extends Window

signal skin_selected(skin_id)
signal notify(message)

const CACHOMON_PUBLIC_URL := "https://cachomon.com/list.php?a=0&g=1&m=0&t=1"

var skin_manager
var config_store
var repo_root := ""
var item_list: ItemList
var detail_label: Label
var import_file_dialog: FileDialog
var import_folder_dialog: FileDialog


func _ready() -> void:
	title = "皮肤管理"
	size = Vector2i(620, 460)
	min_size = Vector2i(520, 380)
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
	var root = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(_on_item_selected)
	root.add_child(item_list)

	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size = Vector2(0, 72)
	root.add_child(detail_label)

	var buttons = HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	root.add_child(buttons)

	_add_button(buttons, "启用", _on_enable_pressed)
	_add_button(buttons, "导入 ZIP", _on_import_zip_pressed)
	_add_button(buttons, "导入文件夹", _on_import_folder_pressed)
	_add_button(buttons, "刷新", _refresh)
	_add_button(buttons, "删除用户皮肤", _on_delete_pressed)
	_add_button(buttons, "打开皮肤目录", _on_open_user_skins_pressed)
	_add_button(buttons, "Cachomon 目录", _on_cachomon_pressed)

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
		var suffix = "  ✓" if skin_id == selected_id else ""
		item_list.add_item("%s [%s]%s" % [str(skin.get("name", skin_id)), kind, suffix])
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
		detail_label.text = "没有可用皮肤。"


func _on_item_selected(index: int) -> void:
	_update_detail(index)


func _update_detail(index: int) -> void:
	if skin_manager == null or index < 0:
		return
	var skin_id = str(item_list.get_item_metadata(index))
	if not skin_manager.has_skin(skin_id):
		return
	var skin = skin_manager.skins_by_id[skin_id]
	var license = skin.get("license", {})
	var license_text = ""
	if typeof(license) == TYPE_DICTIONARY:
		license_text = str(license.get("summary", license.get("type", "")))
	detail_label.text = "%s\nID: %s\n%s" % [str(skin.get("description", "")), skin_id, license_text]


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
		emit_signal("notify", "皮肤导入完成。")
	else:
		emit_signal("notify", "导入失败：%s" % "\n".join(output).left(180))


func _on_delete_pressed() -> void:
	var skin_id = _selected_skin_id()
	if skin_id == "":
		return
	if skin_manager.delete_user_skin(skin_id):
		_refresh()
		emit_signal("notify", "用户皮肤已移到回收站。")
	else:
		emit_signal("notify", "只能删除用户导入的皮肤。")


func _on_open_user_skins_pressed() -> void:
	if skin_manager == null:
		return
	DirAccess.make_dir_recursive_absolute(skin_manager.user_skin_root)
	OS.shell_open(skin_manager.user_skin_root)


func _on_cachomon_pressed() -> void:
	OS.shell_open(CACHOMON_PUBLIC_URL)


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
	var helper = _helper_path()
	if helper != "":
		return OS.execute(helper, [
			"import-shimeji",
			source_path,
			"--output-root",
			skin_manager.user_skin_root,
		], output, true, true)
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
