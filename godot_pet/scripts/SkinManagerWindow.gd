extends Window

signal skin_selected(skin_id)
signal notify(message)

const SkinCatalogClientScript = preload("res://scripts/SkinCatalogClient.gd")

const CACHOMON_PUBLIC_URL := "https://cachomon.com/list.php?a=0&g=1&m=0&t=1"
const TAB_INSTALLED := "installed"
const TAB_ONLINE := "online"
const TAB_IMPORT := "import"
const BG := Color("#f6f7fb")
const SURFACE := Color("#ffffff")
const SURFACE_ALT := Color("#eef4ff")
const TEXT := Color("#202633")
const MUTED := Color("#687184")
const PRIMARY := Color("#2f80ed")
const PRIMARY_DARK := Color("#1d5fb7")
const SECONDARY := Color("#26a978")
const BORDER := Color("#dde3ee")
const WARNING := Color("#e47b4d")
const AMBER := Color("#d99a20")
const ROSE := Color("#d95f7a")
const MAX_ONLINE_CARDS := 120

var skin_manager
var config_store
var repo_root := ""
var catalog_client
var active_tab := TAB_INSTALLED
var tab_buttons := {}
var tab_button_group: ButtonGroup
var content_panels := {}
var installed_list: ItemList
var online_search: LineEdit
var source_filter: OptionButton
var status_filter: OptionButton
var complexity_filter: OptionButton
var online_status_label: Label
var online_grid: GridContainer
var import_report_text: TextEdit
var detail_preview: TextureRect
var detail_title: Label
var detail_status: Label
var detail_meta: Label
var detail_body: Label
var detail_actions: ItemList
var detail_report: TextEdit
var enable_button: Button
var install_button: Button
var delete_button: Button
var progress_bar: ProgressBar
var import_file_dialog: FileDialog
var import_folder_dialog: FileDialog
var delete_confirm: ConfirmationDialog
var pending_delete_skin_id := ""
var selected_installed_id := ""
var selected_online_id := ""
var online_entries := []
var online_by_id := {}
var online_preview_paths := {}
var card_preview_rects := {}
var detail_mode := ""


func _ready() -> void:
	title = "皮肤商店"
	size = Vector2i(1220, 720)
	min_size = Vector2i(1020, 620)
	close_requested.connect(hide)
	files_dropped.connect(_on_files_dropped)
	_build_ui()


func configure(manager, store, root: String) -> void:
	skin_manager = manager
	config_store = store
	repo_root = root
	if skin_manager != null:
		skin_manager.skins_changed.connect(_refresh)
	catalog_client = SkinCatalogClientScript.new()
	add_child(catalog_client)
	var config_dir = config_store.config_dir if config_store != null else ProjectSettings.globalize_path("user://")
	catalog_client.configure(repo_root, config_dir)
	catalog_client.catalog_loaded.connect(_on_catalog_loaded)
	catalog_client.catalog_failed.connect(_on_catalog_failed)
	catalog_client.preview_ready.connect(_on_preview_ready)
	catalog_client.download_progress.connect(_on_download_progress)
	catalog_client.skin_downloaded.connect(_on_skin_downloaded)
	catalog_client.skin_download_failed.connect(_on_skin_download_failed)


func open_window() -> void:
	_refresh()
	_switch_tab(TAB_ONLINE)
	popup_centered()
	call_deferred("_load_catalog")


func _load_catalog() -> void:
	if online_status_label != null:
		online_status_label.text = "正在加载 Shimeji 皮肤商店..."
	if catalog_client != null:
		catalog_client.load_catalog()


func _build_ui() -> void:
	var background = PanelContainer.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", _style(BG, BG, 0, 0))
	add_child(background)

	var root_margin = MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	background.add_child(root_margin)

	var root = HBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root_margin.add_child(root)

	root.add_child(_build_sidebar())

	var main = HSplitContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	var content_stack = Control.new()
	content_stack.custom_minimum_size = Vector2(650, 0)
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(content_stack)

	content_panels[TAB_INSTALLED] = _build_installed_panel()
	content_panels[TAB_ONLINE] = _build_online_panel()
	content_panels[TAB_IMPORT] = _build_import_panel()
	for tab in content_panels.keys():
		var panel: Control = content_panels[tab]
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		content_stack.add_child(panel)

	main.add_child(_build_detail_panel())
	_build_dialogs()
	_switch_tab(TAB_INSTALLED)


func _build_sidebar() -> Control:
	var sidebar = PanelContainer.new()
	sidebar.custom_minimum_size = Vector2(164, 0)
	sidebar.add_theme_stylebox_override("panel", _style(SURFACE, BORDER, 1, 8))

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	sidebar.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title_label = _make_label(20, TEXT)
	title_label.text = "皮肤商店"
	box.add_child(title_label)

	tab_button_group = ButtonGroup.new()
	_add_tab_button(box, TAB_ONLINE, "发现")
	_add_tab_button(box, TAB_INSTALLED, "已安装")
	_add_tab_button(box, TAB_IMPORT, "导入")

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var folder_button = _make_button("皮肤目录", SECONDARY)
	folder_button.pressed.connect(_on_open_user_skins_pressed)
	box.add_child(folder_button)

	var cachomon_button = _make_button("Cachomon", Color("#f2b84b"))
	cachomon_button.pressed.connect(_on_cachomon_pressed)
	box.add_child(cachomon_button)
	return sidebar


func _add_tab_button(parent: Control, tab: String, text: String) -> void:
	var button = _make_button(text, PRIMARY)
	button.toggle_mode = true
	button.button_group = tab_button_group
	button.pressed.connect(func(): _switch_tab(tab))
	parent.add_child(button)
	tab_buttons[tab] = button


func _build_installed_panel() -> Control:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(SURFACE, BORDER, 1, 8))
	var margin = _content_margin()
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	box.add_child(toolbar)
	var refresh_button = _make_button("刷新", SECONDARY)
	refresh_button.pressed.connect(_refresh)
	toolbar.add_child(refresh_button)
	var enable_selected = _make_button("启用", PRIMARY)
	enable_selected.pressed.connect(_on_enable_pressed)
	toolbar.add_child(enable_selected)

	installed_list = ItemList.new()
	installed_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	installed_list.item_selected.connect(_on_installed_item_selected)
	box.add_child(installed_list)
	return panel


func _build_online_panel() -> Control:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(SURFACE, BORDER, 1, 8))
	var margin = _content_margin()
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	box.add_child(toolbar)

	source_filter = OptionButton.new()
	source_filter.custom_minimum_size = Vector2(112, 34)
	_add_filter_item(source_filter, "Shimeji", "shimeji")
	_add_filter_item(source_filter, "全部", "all")
	_add_filter_item(source_filter, "精选", "curated")
	source_filter.item_selected.connect(func(_index): _fill_online_grid())
	toolbar.add_child(source_filter)

	status_filter = OptionButton.new()
	status_filter.custom_minimum_size = Vector2(104, 34)
	_add_filter_item(status_filter, "全部状态", "all")
	_add_filter_item(status_filter, "可下载", "free")
	_add_filter_item(status_filter, "Beta", "beta")
	_add_filter_item(status_filter, "Patreon", "patreon")
	_add_filter_item(status_filter, "不可下载", "unavailable")
	status_filter.item_selected.connect(func(_index): _fill_online_grid())
	toolbar.add_child(status_filter)

	complexity_filter = OptionButton.new()
	complexity_filter.custom_minimum_size = Vector2(116, 34)
	_add_filter_item(complexity_filter, "全部难度", "all")
	for level in ["Super Easy", "Easy", "Regular", "Difficult", "Extreme", "Madness"]:
		_add_filter_item(complexity_filter, level, level.to_lower())
	complexity_filter.item_selected.connect(func(_index): _fill_online_grid())
	toolbar.add_child(complexity_filter)

	online_search = LineEdit.new()
	online_search.placeholder_text = "搜索 Eevee、Pikmin、作者或特性"
	online_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online_search.text_changed.connect(func(_text): _fill_online_grid())
	toolbar.add_child(online_search)
	var reload_button = _make_button("刷新商店", SECONDARY)
	reload_button.pressed.connect(func():
		online_status_label.text = "正在刷新皮肤商店..."
		if catalog_client != null:
			catalog_client.load_catalog()
	)
	toolbar.add_child(reload_button)

	online_status_label = _make_label(13, MUTED)
	online_status_label.text = "正在加载 Shimeji 皮肤商店..."
	box.add_child(online_status_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	online_grid = GridContainer.new()
	online_grid.columns = 3
	online_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online_grid.add_theme_constant_override("h_separation", 10)
	online_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(online_grid)
	return panel


func _build_import_panel() -> Control:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(SURFACE, BORDER, 1, 8))
	var margin = _content_margin()
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var buttons = HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	box.add_child(buttons)
	var zip_button = _make_button("导入 ZIP", PRIMARY)
	zip_button.pressed.connect(_on_import_zip_pressed)
	buttons.add_child(zip_button)
	var folder_button = _make_button("导入文件夹", PRIMARY)
	folder_button.pressed.connect(_on_import_folder_pressed)
	buttons.add_child(folder_button)
	var dir_button = _make_button("打开目录", SECONDARY)
	dir_button.pressed.connect(_on_open_user_skins_pressed)
	buttons.add_child(dir_button)
	var web_button = _make_button("浏览 Cachomon", Color("#f2b84b"))
	web_button.pressed.connect(_on_cachomon_pressed)
	buttons.add_child(web_button)

	import_report_text = TextEdit.new()
	import_report_text.editable = false
	import_report_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	import_report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	import_report_text.text = "等待导入。"
	box.add_child(import_report_text)
	return panel


func _build_detail_panel() -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_stylebox_override("panel", _style(SURFACE, BORDER, 1, 8))
	var margin = _content_margin()
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	detail_preview = TextureRect.new()
	detail_preview.custom_minimum_size = Vector2(190, 190)
	detail_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(detail_preview)

	detail_title = _make_label(22, TEXT)
	box.add_child(detail_title)
	detail_status = _make_label(14, PRIMARY_DARK)
	box.add_child(detail_status)
	detail_meta = _make_label(13, MUTED)
	box.add_child(detail_meta)
	detail_body = _make_label(13, TEXT)
	box.add_child(detail_body)

	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	box.add_child(actions)
	enable_button = _make_button("启用", PRIMARY)
	enable_button.pressed.connect(_on_enable_pressed)
	actions.add_child(enable_button)
	install_button = _make_button("下载并安装", PRIMARY)
	install_button.pressed.connect(func(): _on_online_install_pressed(""))
	actions.add_child(install_button)
	delete_button = _make_button("删除", WARNING)
	delete_button.pressed.connect(_on_delete_pressed)
	actions.add_child(delete_button)

	progress_bar = ProgressBar.new()
	progress_bar.visible = false
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	box.add_child(progress_bar)

	detail_actions = ItemList.new()
	detail_actions.custom_minimum_size = Vector2(0, 132)
	detail_actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(detail_actions)

	detail_report = TextEdit.new()
	detail_report.custom_minimum_size = Vector2(0, 110)
	detail_report.editable = false
	detail_report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(detail_report)
	return panel


func _build_dialogs() -> void:
	import_file_dialog = FileDialog.new()
	import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_file_dialog.filters = PackedStringArray(["*.zip ; MascotMate or Shimeji ZIP"])
	import_file_dialog.file_selected.connect(_on_import_source_selected)
	import_file_dialog.current_dir = _downloads_dir()
	add_child(import_file_dialog)

	import_folder_dialog = FileDialog.new()
	import_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	import_folder_dialog.current_dir = _downloads_dir()
	import_folder_dialog.dir_selected.connect(_on_import_source_selected)
	add_child(import_folder_dialog)

	delete_confirm = ConfirmationDialog.new()
	delete_confirm.title = "删除用户皮肤"
	delete_confirm.dialog_text = "确定要把这个用户皮肤移到回收站吗？"
	delete_confirm.confirmed.connect(_delete_selected_user_skin)
	add_child(delete_confirm)


func _content_margin() -> MarginContainer:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	return margin


func _style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_label(font_size: int, color: Color) -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_badge(text: String, color: Color) -> Label:
	var label = _make_label(12, Color.WHITE)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 24)
	var style = _style(color, color, 0, 8)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_TOP, 3)
	style.set_content_margin(SIDE_BOTTOM, 3)
	label.add_theme_stylebox_override("normal", style)
	return label


func _make_button(text: String, color: Color) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(color, color, 0, 8))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.08), color.lightened(0.08), 0, 8))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.08), color.darkened(0.08), 0, 8))
	button.add_theme_stylebox_override("disabled", _style(Color("#cbd5cf"), Color("#cbd5cf"), 0, 8))
	return button


func _add_filter_item(button: OptionButton, label: String, value: String) -> void:
	button.add_item(label)
	button.set_item_metadata(button.item_count - 1, value)


func _selected_filter_value(button: OptionButton, fallback: String) -> String:
	if button == null or button.item_count == 0:
		return fallback
	var metadata = button.get_item_metadata(button.selected)
	return str(metadata) if metadata != null else fallback


func _switch_tab(tab: String) -> void:
	active_tab = tab
	for key in content_panels.keys():
		content_panels[key].visible = key == tab
	for key in tab_buttons.keys():
		tab_buttons[key].button_pressed = key == tab
	if tab == TAB_INSTALLED:
		_show_selected_installed_detail()
	elif tab == TAB_ONLINE:
		if selected_online_id == "" and not online_entries.is_empty():
			_select_online(str(online_entries[0].get("id", "")))
		elif selected_online_id != "":
			_select_online(selected_online_id)
		else:
			_clear_detail("皮肤商店")
	elif tab == TAB_IMPORT:
		_show_import_detail()


func _refresh() -> void:
	_refresh_installed_list()
	_fill_online_grid()
	if active_tab == TAB_INSTALLED:
		_show_selected_installed_detail()
	elif active_tab == TAB_ONLINE and selected_online_id != "":
		_select_online(selected_online_id)


func _refresh_installed_list() -> void:
	if installed_list == null or skin_manager == null:
		return
	installed_list.clear()
	var selected_id = skin_manager.selected_skin_id()
	var selected_index := -1
	var index := 0
	for skin in skin_manager.list_skins():
		var skin_id = str(skin.get("id", ""))
		var kind = str(skin.get("_kind", ""))
		var metadata = skin.get("metadata", {})
		var level = str(metadata.get("compatibility_level", "minimal")) if typeof(metadata) == TYPE_DICTIONARY else "minimal"
		var suffix = "  ✓" if skin_id == selected_id else ""
		installed_list.add_item("%s  [%s/%s]%s" % [str(skin.get("name", skin_id)), kind, level, suffix])
		installed_list.set_item_metadata(index, skin_id)
		if selected_installed_id == "":
			selected_installed_id = selected_id
		if skin_id == selected_installed_id:
			selected_index = index
		index += 1
	if selected_index >= 0:
		installed_list.select(selected_index)
	elif installed_list.item_count > 0:
		installed_list.select(0)
		selected_installed_id = str(installed_list.get_item_metadata(0))


func _on_installed_item_selected(index: int) -> void:
	selected_installed_id = str(installed_list.get_item_metadata(index))
	_show_installed_detail(selected_installed_id)


func _show_selected_installed_detail() -> void:
	if selected_installed_id == "" and installed_list != null and installed_list.item_count > 0:
		selected_installed_id = str(installed_list.get_item_metadata(0))
	if selected_installed_id != "":
		_show_installed_detail(selected_installed_id)
	else:
		_clear_detail("没有可用皮肤")


func _show_installed_detail(skin_id: String) -> void:
	if skin_manager == null or not skin_manager.has_skin(skin_id):
		_clear_detail("没有可用皮肤")
		return
	detail_mode = TAB_INSTALLED
	var skin = skin_manager.skins_by_id[skin_id]
	var metadata: Dictionary = skin.get("metadata", {})
	var source: Dictionary = skin.get("source", {})
	var license: Dictionary = skin.get("license", {})
	detail_title.text = str(skin.get("name", skin_id))
	detail_status.text = "当前启用" if skin_id == skin_manager.selected_skin_id() else "已安装"
	detail_meta.text = "ID: %s\n类型: %s  版本: %s  作者: %s\n来源: %s %s" % [
		skin_id,
		str(skin.get("_kind", "")),
		str(metadata.get("package_version", "1.0.0")),
		_format_authors(metadata.get("authors", [])),
		str(source.get("format", "skin-json")),
		str(source.get("image_set", "")),
	]
	detail_body.text = "兼容：%s  %d/100\n能力覆盖：%s\n授权：%s；可再分发：%s\n%s" % [
		str(metadata.get("compatibility_level", "minimal")),
		int(metadata.get("compatibility_score", 0)),
		_format_coverage(metadata.get("capability_coverage", {})),
		str(license.get("type", "unknown")),
		"是" if bool(license.get("redistributable", false)) else "否",
		str(license.get("summary", "")),
	]
	_load_installed_preview(skin)
	_fill_action_list(skin)
	detail_actions.visible = true
	detail_report.visible = true
	detail_report.text = _format_report(skin)
	enable_button.visible = true
	enable_button.disabled = skin_id == skin_manager.selected_skin_id()
	install_button.visible = false
	delete_button.visible = str(skin.get("_kind", "")) == "user"
	progress_bar.visible = false


func _show_import_detail() -> void:
	detail_mode = TAB_IMPORT
	detail_preview.texture = null
	detail_title.text = "导入皮肤"
	detail_status.text = "本地安装"
	detail_meta.text = "支持 MascotMate 原生皮肤包和 Shimeji-ee ZIP/文件夹。"
	detail_body.text = "用户提供素材的授权由用户自行确认。"
	detail_actions.clear()
	detail_actions.visible = false
	detail_report.visible = true
	detail_report.text = import_report_text.text if import_report_text != null else ""
	enable_button.visible = false
	install_button.visible = false
	delete_button.visible = false
	progress_bar.visible = false


func _clear_detail(message: String) -> void:
	detail_mode = ""
	detail_preview.texture = null
	detail_title.text = message
	detail_status.text = ""
	detail_meta.text = ""
	detail_body.text = ""
	detail_actions.clear()
	detail_actions.visible = true
	detail_report.visible = true
	detail_report.text = ""
	enable_button.visible = false
	install_button.visible = false
	delete_button.visible = false
	progress_bar.visible = false


func _on_catalog_loaded(loaded_entries: Array, source_label: String, offline: bool) -> void:
	online_entries = loaded_entries
	online_by_id = {}
	var external_count := 0
	var curated_count := 0
	for entry in online_entries:
		if typeof(entry) == TYPE_DICTIONARY:
			online_by_id[str(entry.get("id", ""))] = entry
			if str(entry.get("source_type", "")) == "external_browser":
				external_count += 1
			else:
				curated_count += 1
	online_status_label.text = "%s：%d 个 Shimeji，%d 个精选%s" % [source_label, external_count, curated_count, "（本地缓存）" if offline else ""]
	_fill_online_grid()
	if active_tab == TAB_ONLINE:
		if selected_online_id == "" and not online_entries.is_empty():
			_select_online(str(online_entries[0].get("id", "")))
		elif selected_online_id != "":
			_select_online(selected_online_id)


func _on_catalog_failed(message: String) -> void:
	online_status_label.text = message
	_fill_online_grid()
	if active_tab == TAB_ONLINE:
		_clear_detail("皮肤商店暂不可用")


func _fill_online_grid() -> void:
	if online_grid == null:
		return
	for child in online_grid.get_children():
		child.queue_free()
	card_preview_rects = {}
	var query = online_search.text.strip_edges().to_lower() if online_search != null else ""
	var visible_count := 0
	for entry in online_entries:
		if typeof(entry) != TYPE_DICTIONARY or not _entry_matches_filters(entry, query):
			continue
		if visible_count >= MAX_ONLINE_CARDS:
			break
		online_grid.add_child(_make_online_card(entry))
		if catalog_client != null:
			catalog_client.request_preview(entry)
		visible_count += 1
	if visible_count == 0:
		var empty = _make_label(14, MUTED)
		empty.text = "没有匹配的皮肤。"
		online_grid.add_child(empty)
	elif visible_count >= MAX_ONLINE_CARDS:
		var more = _make_label(13, MUTED)
		more.text = "已显示前 %d 个结果，继续搜索可缩小范围。" % MAX_ONLINE_CARDS
		online_grid.add_child(more)


func _entry_matches_filters(entry: Dictionary, query: String) -> bool:
	var source_value = _selected_filter_value(source_filter, "shimeji")
	var source_type = str(entry.get("source_type", "curated_package"))
	if source_value == "shimeji" and source_type != "external_browser":
		return false
	if source_value == "curated" and source_type != "curated_package":
		return false
	var status_value = _selected_filter_value(status_filter, "all")
	if status_value != "all" and str(entry.get("status", "")) != status_value:
		return false
	var complexity_value = _selected_filter_value(complexity_filter, "all")
	if complexity_value != "all" and str(entry.get("complexity", "")).to_lower() != complexity_value:
		return false
	if query == "":
		return true
	var haystack = "%s %s %s %s" % [
		str(entry.get("id", "")),
		str(entry.get("name", "")),
		str(entry.get("description", "")),
		str(entry.get("artist", "")),
		" ".join(entry.get("tags", [])) if typeof(entry.get("tags", [])) == TYPE_ARRAY else "",
	]
	return haystack.to_lower().find(query) >= 0


func _make_online_card(entry: Dictionary) -> Control:
	var skin_id = str(entry.get("id", ""))
	var installed = skin_manager != null and skin_manager.has_skin(skin_id)
	var source_type = str(entry.get("source_type", "curated_package"))
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(206, 284)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _style(SURFACE_ALT if skin_id == selected_online_id else SURFACE, BORDER, 1, 8))
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_online(skin_id)
	)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var preview_shell = PanelContainer.new()
	preview_shell.custom_minimum_size = Vector2(0, 132)
	preview_shell.add_theme_stylebox_override("panel", _style(Color("#f8fbff"), BORDER, 1, 8))
	box.add_child(preview_shell)

	var preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(0, 132)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if online_preview_paths.has(skin_id):
		preview.texture = _texture_from_file(str(online_preview_paths[skin_id]))
	preview_shell.add_child(preview)
	card_preview_rects[skin_id] = preview

	var badges = HFlowContainer.new()
	badges.add_theme_constant_override("h_separation", 6)
	badges.add_theme_constant_override("v_separation", 4)
	if source_type == "external_browser":
		badges.add_child(_make_badge(_status_text(str(entry.get("status", ""))), _status_color(str(entry.get("status", "")))))
		var complexity = str(entry.get("complexity", ""))
		if complexity != "":
			badges.add_child(_make_badge(complexity, SECONDARY))
	else:
		badges.add_child(_make_badge("精选", SECONDARY))
	if installed:
		badges.add_child(_make_badge("已安装", PRIMARY_DARK))
	box.add_child(badges)

	var name_label = _make_label(16, TEXT)
	name_label.text = str(entry.get("name", skin_id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)
	var byline = _make_label(12, MUTED)
	byline.text = _card_byline(entry)
	byline.autowrap_mode = TextServer.AUTOWRAP_OFF
	byline.clip_text = true
	byline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(byline)
	var meta = _make_label(12, MUTED)
	meta.text = _card_meta(entry, installed)
	box.add_child(meta)

	var button_text = "启用" if installed else ("打开原站" if source_type == "external_browser" else "安装")
	var button_color = SECONDARY if installed else (PRIMARY if source_type == "external_browser" else SECONDARY)
	var button = _make_button(button_text, button_color)
	button.pressed.connect(func(): _on_online_install_pressed(skin_id))
	box.add_child(button)
	return card


func _card_meta(entry: Dictionary, installed: bool) -> String:
	if installed:
		return "已安装"
	if str(entry.get("source_type", "")) == "external_browser":
		return "%s 次下载" % _format_count(int(entry.get("downloads", 0)))
	return "精选  %s" % _format_size(int(entry.get("size_bytes", 0)))


func _card_byline(entry: Dictionary) -> String:
	if str(entry.get("source_type", "")) == "external_browser":
		var artist = str(entry.get("artist", ""))
		return "by %s" % artist if artist != "" else "Cachomon"
	var tags = entry.get("tags", [])
	return ", ".join(tags).left(64) if typeof(tags) == TYPE_ARRAY else "MascotMate"


func _select_online(skin_id: String) -> void:
	if not online_by_id.has(skin_id):
		if online_entries.is_empty():
			_clear_detail("皮肤商店")
		return
	selected_online_id = skin_id
	_show_online_detail(online_by_id[skin_id])
	_fill_online_grid()


func _show_online_detail(entry: Dictionary) -> void:
	detail_mode = TAB_ONLINE
	var skin_id = str(entry.get("id", ""))
	var installed = skin_manager != null and skin_manager.has_skin(skin_id)
	var source_type = str(entry.get("source_type", "curated_package"))
	detail_title.text = str(entry.get("name", skin_id))
	detail_actions.clear()
	if source_type == "external_browser":
		detail_status.text = _status_text(str(entry.get("status", "")))
		detail_meta.text = "作者: %s\n难度: %s  下载量: %s\n安全级别: %s\n特性: %s" % [
			str(entry.get("artist", "未知")),
			str(entry.get("complexity", "")),
			_format_count(int(entry.get("downloads", 0))),
			str(entry.get("safe_level", "sfw")).to_upper(),
			", ".join(entry.get("features", [])) if typeof(entry.get("features", [])) == TYPE_ARRAY else "",
		]
		detail_body.text = "打开原站页面下载 ZIP；下载完成后，把 ZIP 拖进这个窗口或使用“导入 ZIP”安装。应用不会镜像或代下载第三方皮肤包。"
		detail_report.visible = false
		detail_actions.visible = false
	else:
		detail_status.text = "已安装" if installed else "精选可安装"
		detail_meta.text = "格式: %s  版本要求: %s\n标签: %s\n大小: %s" % [
			str(entry.get("format", "")),
			str(entry.get("min_app_version", "")),
			", ".join(entry.get("tags", [])) if typeof(entry.get("tags", [])) == TYPE_ARRAY else "",
			_format_size(int(entry.get("size_bytes", 0))),
		]
		var license = entry.get("license", {})
		detail_body.text = "%s\n\n授权：%s；可再分发：%s" % [
			str(entry.get("description", "")),
			str(license.get("type", "unknown")) if typeof(license) == TYPE_DICTIONARY else "unknown",
			"是" if typeof(license) == TYPE_DICTIONARY and bool(license.get("redistributable", false)) else "否",
		]
		detail_actions.visible = true
		detail_report.visible = true
		detail_actions.add_item("SHA-256: %s" % str(entry.get("sha256", "")).left(24))
		detail_actions.add_item("来源: curated catalog")
		detail_report.text = "下载安装到用户皮肤目录后会自动刷新并启用。"
	detail_preview.texture = null
	if online_preview_paths.has(skin_id):
		detail_preview.texture = _texture_from_file(str(online_preview_paths[skin_id]))
	enable_button.visible = installed and source_type != "external_browser"
	enable_button.disabled = false
	install_button.visible = true
	install_button.disabled = installed and source_type != "external_browser"
	install_button.text = "打开原站" if source_type == "external_browser" else ("已安装" if installed else "下载并安装")
	delete_button.visible = false
	progress_bar.visible = false


func _on_preview_ready(skin_id: String, path: String) -> void:
	online_preview_paths[skin_id] = path
	if card_preview_rects.has(skin_id) and is_instance_valid(card_preview_rects[skin_id]):
		card_preview_rects[skin_id].texture = _texture_from_file(path)
	if selected_online_id == skin_id and detail_mode == TAB_ONLINE:
		detail_preview.texture = _texture_from_file(path)


func _on_online_install_pressed(skin_id: String) -> void:
	var target_id = skin_id if skin_id != "" else selected_online_id
	if target_id == "" or not online_by_id.has(target_id):
		return
	var entry: Dictionary = online_by_id[target_id]
	if str(entry.get("source_type", "curated_package")) == "external_browser":
		var source_url = str(entry.get("source_url", ""))
		if source_url != "":
			OS.shell_open(source_url)
			emit_signal("notify", "已打开原站页面。下载 ZIP 后可拖入或导入。")
		return
	if skin_manager != null and skin_manager.has_skin(target_id):
		emit_signal("skin_selected", target_id)
		return
	progress_bar.visible = true
	progress_bar.value = 0
	install_button.disabled = true
	install_button.text = "下载中..."
	detail_report.text = "正在下载皮肤包。"
	catalog_client.download_skin(entry)


func _on_download_progress(skin_id: String, downloaded_bytes: int, total_bytes: int) -> void:
	if selected_online_id != skin_id:
		return
	progress_bar.visible = true
	if total_bytes > 0:
		progress_bar.value = clamp(float(downloaded_bytes) / float(total_bytes) * 100.0, 0.0, 100.0)
	else:
		progress_bar.value = fmod(progress_bar.value + 6.0, 100.0)
	detail_report.text = "正在下载：%s / %s" % [_format_size(downloaded_bytes), _format_size(total_bytes)]


func _on_skin_downloaded(skin_id: String, path: String) -> void:
	var output := []
	var code = _run_installer(path, output)
	progress_bar.visible = false
	if code == 0:
		skin_manager.reload_skins()
		var installed_id = _installed_skin_id_from_output(output)
		if installed_id == "":
			installed_id = skin_id
		selected_installed_id = installed_id
		if skin_manager.has_skin(installed_id):
			emit_signal("skin_selected", installed_id)
		_refresh()
		_select_online(skin_id)
		var message = _import_summary(output)
		emit_signal("notify", message)
	else:
		var text = "\n".join(output)
		detail_report.text = _clean_error_text(text)
		install_button.disabled = false
		install_button.text = "重试安装"
		emit_signal("notify", "安装失败：%s" % _clean_error_text(text).left(180))


func _on_skin_download_failed(skin_id: String, message: String) -> void:
	if selected_online_id == skin_id:
		progress_bar.visible = false
		install_button.disabled = false
		install_button.text = "重试下载"
		detail_report.text = message
	emit_signal("notify", message)


func _on_enable_pressed() -> void:
	if detail_mode == TAB_ONLINE and selected_online_id != "":
		if skin_manager != null and skin_manager.has_skin(selected_online_id):
			emit_signal("skin_selected", selected_online_id)
		return
	var skin_id = selected_installed_id
	if skin_id != "":
		emit_signal("skin_selected", skin_id)


func _on_import_zip_pressed() -> void:
	import_file_dialog.current_dir = _downloads_dir()
	import_file_dialog.popup_centered(Vector2i(720, 460))


func _on_import_folder_pressed() -> void:
	import_folder_dialog.current_dir = _downloads_dir()
	import_folder_dialog.popup_centered(Vector2i(720, 460))


func _on_import_source_selected(path: String) -> void:
	if skin_manager == null:
		return
	DirAccess.make_dir_recursive_absolute(skin_manager.user_skin_root)
	var output := []
	var code = _run_installer(path, output)
	if code == 0:
		skin_manager.reload_skins()
		var installed_id = _installed_skin_id_from_output(output)
		if installed_id != "" and skin_manager.has_skin(installed_id):
			selected_installed_id = installed_id
			emit_signal("skin_selected", installed_id)
		_refresh()
		var message = _import_summary(output)
		import_report_text.text = message
		detail_report.text = message
		emit_signal("notify", message)
	else:
		var text = "\n".join(output)
		var clean = _clean_error_text(text)
		import_report_text.text = clean
		detail_report.text = clean
		emit_signal("notify", "导入失败：%s" % clean.left(180))


func _on_delete_pressed() -> void:
	var skin_id = selected_installed_id
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
		selected_installed_id = skin_manager.selected_skin_id()
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
	detail_actions.clear()
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
		detail_actions.add_item("%s  %s  %d frames%s" % [
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
	if typeof(parsed) != TYPE_ARRAY or parsed.is_empty():
		return "皮肤安装完成。"
	var report = parsed[0].get("report", {}) if typeof(parsed[0]) == TYPE_DICTIONARY else {}
	if typeof(report) != TYPE_DICTIONARY:
		return "皮肤安装完成。"
	return "皮肤安装完成：%s %d/100。" % [
		str(report.get("compatibility_level", "minimal")),
		int(report.get("compatibility_score", 0)),
	]


func _installed_skin_id_from_output(output: Array) -> String:
	var parsed = JSON.parse_string("\n".join(output))
	if typeof(parsed) != TYPE_ARRAY or parsed.is_empty():
		return ""
	var report = parsed[0].get("report", {}) if typeof(parsed[0]) == TYPE_DICTIONARY else {}
	if typeof(report) == TYPE_DICTIONARY:
		return str(report.get("skin_id", ""))
	return ""


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


func _format_size(bytes: int) -> String:
	if bytes <= 0:
		return "未知大小"
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / 1024.0 / 1024.0)
	if bytes >= 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes


func _format_count(value: int) -> String:
	if value >= 10000:
		return "%.1f万" % (float(value) / 10000.0)
	return "%d" % value


func _status_text(status: String) -> String:
	match status:
		"free":
			return "可下载"
		"beta":
			return "Beta"
		"patreon":
			return "Patreon"
		"unavailable":
			return "不可下载"
		_:
			return "外部页面"


func _status_color(status: String) -> Color:
	match status:
		"free":
			return SECONDARY
		"beta":
			return PRIMARY
		"patreon":
			return AMBER
		"unavailable":
			return MUTED
		_:
			return PRIMARY_DARK


func _downloads_dir() -> String:
	var home = OS.get_environment("HOME")
	if home != "":
		var downloads = home.path_join("Downloads")
		if DirAccess.dir_exists_absolute(downloads):
			return downloads
	return OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)


func _on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if str(path).get_extension().to_lower() == "zip" or DirAccess.dir_exists_absolute(str(path)):
			_switch_tab(TAB_IMPORT)
			_on_import_source_selected(str(path))
			return
	emit_signal("notify", "请拖入 ZIP 皮肤包或已解压文件夹。")


func _clean_error_text(text: String) -> String:
	var clean = text.strip_edges()
	if clean == "":
		return "皮肤安装失败。"
	var parsed = JSON.parse_string(clean)
	if typeof(parsed) == TYPE_ARRAY:
		return "皮肤安装失败，请确认 ZIP 是有效的 MascotMate 或 Shimeji-ee 皮肤包。"
	clean = clean.replace("pet_helper.py:", "").strip_edges()
	if clean.length() > 600:
		clean = clean.left(600) + "..."
	return clean


func _load_installed_preview(skin: Dictionary) -> void:
	detail_preview.texture = null
	var preview = str(skin.get("preview", ""))
	var frame_root = str(skin.get("_frame_root_abs", ""))
	if preview == "" or frame_root == "":
		return
	var path = frame_root.path_join(preview)
	if FileAccess.file_exists(path):
		detail_preview.texture = _texture_from_file(path)


func _texture_from_file(path: String):
	var image = Image.new()
	if image.load(path) == OK:
		return ImageTexture.create_from_image(image)
	return null


func _run_installer(source_path: String, output: Array) -> int:
	var args = [
		"install-skin",
		source_path,
		"--output-root",
		skin_manager.user_skin_root,
		"--json-report",
	]
	var helper = _helper_path()
	if helper != "":
		return OS.execute(helper, args, output, true, true)
	var helper_script = _helper_script_path()
	if helper_script == "":
		output.append("pet_helper.py not found")
		return 2
	var python = _find_python()
	if python == "":
		output.append("Python not found")
		return 2
	return OS.execute(python, [helper_script] + args, output, true, true)


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
