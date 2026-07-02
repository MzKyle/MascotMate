extends Node

signal config_changed(config)

const CONFIG_DIR_NAME := "crayon-shinchan-desktop-pet"
const DEFAULT_CONFIG := {
	"version": 1,
	"app": {
		"display_scale": 1.0,
		"gravity_enabled": true,
		"skin_id": "classic_shinchan",
	},
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

var config := DEFAULT_CONFIG.duplicate(true)
var config_dir := ""
var config_path := ""


func configure() -> void:
	config_dir = _config_dir()
	config_path = config_dir.path_join("config.json")
	load_config()


func load_config() -> void:
	config = DEFAULT_CONFIG.duplicate(true)
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				config = _merged_config(parsed)
	save_config(false)


func save_config(emit_change := true) -> void:
	DirAccess.make_dir_recursive_absolute(config_dir)
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(config, "\t"))
	if emit_change:
		emit_signal("config_changed", get_config())


func get_config() -> Dictionary:
	return config.duplicate(true)


func app_config() -> Dictionary:
	return config.get("app", {}).duplicate(true)


func screenshot_pins_config() -> Dictionary:
	return {
		"shortcuts": config.get("shortcuts", {}).duplicate(true),
		"screenshot": config.get("screenshot", {}).duplicate(true),
		"pins": config.get("pins", {}).duplicate(true),
	}


func set_app_config(values: Dictionary) -> void:
	if not config.has("app") or typeof(config["app"]) != TYPE_DICTIONARY:
		config["app"] = DEFAULT_CONFIG["app"].duplicate(true)
	if values.has("display_scale"):
		config["app"]["display_scale"] = clamp(float(values["display_scale"]), 1.0, 1.5)
	if values.has("gravity_enabled"):
		config["app"]["gravity_enabled"] = bool(values["gravity_enabled"])
	if values.has("skin_id"):
		var skin_id = str(values["skin_id"]).strip_edges()
		config["app"]["skin_id"] = skin_id if skin_id != "" else "classic_shinchan"
	save_config()


func set_screenshot_pins_config(values: Dictionary) -> void:
	config = _merged_config(_merge_top_level(config, values))
	save_config()


func _merge_top_level(base: Dictionary, values: Dictionary) -> Dictionary:
	var merged = base.duplicate(true)
	for key in values.keys():
		merged[key] = values[key]
	return merged


func _merged_config(source: Dictionary) -> Dictionary:
	var merged = DEFAULT_CONFIG.duplicate(true)
	merged["version"] = 1

	if source.has("app") and typeof(source["app"]) == TYPE_DICTIONARY:
		if source["app"].has("display_scale"):
			merged["app"]["display_scale"] = clamp(float(source["app"]["display_scale"]), 1.0, 1.5)
		if source["app"].has("gravity_enabled"):
			merged["app"]["gravity_enabled"] = bool(source["app"]["gravity_enabled"])
		if source["app"].has("skin_id"):
			var skin_id = str(source["app"]["skin_id"]).strip_edges()
			merged["app"]["skin_id"] = skin_id if skin_id != "" else "classic_shinchan"

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


func _config_dir() -> String:
	var override_dir = OS.get_environment("CRAYON_PET_CONFIG_DIR").strip_edges()
	if override_dir != "":
		return override_dir
	if OS.get_name() != "Windows" and OS.get_name() != "macOS":
		var home = OS.get_environment("HOME")
		if home != "":
			return home.path_join(".config").path_join(CONFIG_DIR_NAME)
	return ProjectSettings.globalize_path("user://")
