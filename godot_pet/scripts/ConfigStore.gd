extends Node

signal config_changed(config)

const CONFIG_DIR_NAME := "mascotmate-desktop"
const DEFAULT_CONFIG := {
	"version": 1,
	"app": {
		"display_scale": 1.0,
		"gravity_enabled": true,
		"skin_id": "classic_shinchan",
		"dialogue_tone": "gentle",
		"behavior_adaptation": {
			"enabled": true,
			"strength": "visible",
		},
		"ai_expression": {
			"enabled": false,
			"provider": "local_stub",
			"timeout_ms": 800,
		},
		"ai_memory_summary": {
			"enabled": false,
			"provider": "local_stub",
			"timeout_ms": 1500,
			"min_events": 12,
			"min_interval_seconds": 86400,
		},
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


func normalize_dialogue_tone(value) -> String:
	var tone = str(value).strip_edges()
	return tone if tone in ["gentle", "short_cute", "calm"] else "gentle"


func normalize_behavior_adaptation(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["behavior_adaptation"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	if value.has("enabled"):
		merged["enabled"] = bool(value["enabled"])
	if value.has("strength"):
		var strength = str(value["strength"])
		merged["strength"] = strength if strength in ["subtle", "visible", "bold"] else "visible"
	return merged


func normalize_ai_expression(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["ai_expression"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	if value.has("enabled"):
		merged["enabled"] = bool(value["enabled"])
	if value.has("provider"):
		var provider = str(value["provider"])
		merged["provider"] = provider if provider in ["local_stub", "openai_compatible"] else "local_stub"
	if value.has("timeout_ms"):
		merged["timeout_ms"] = clampi(int(value["timeout_ms"]), 100, 5000)
	return merged


func normalize_ai_memory_summary(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["ai_memory_summary"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	if value.has("enabled"):
		merged["enabled"] = bool(value["enabled"])
	if value.has("provider"):
		var provider = str(value["provider"])
		merged["provider"] = provider if provider in ["local_stub", "openai_compatible"] else "local_stub"
	if value.has("timeout_ms"):
		merged["timeout_ms"] = clampi(int(value["timeout_ms"]), 100, 5000)
	if value.has("min_events"):
		merged["min_events"] = clampi(int(value["min_events"]), 1, 200)
	if value.has("min_interval_seconds"):
		merged["min_interval_seconds"] = clampi(int(value["min_interval_seconds"]), 60, 30 * 24 * 60 * 60)
	return merged


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
	if values.has("dialogue_tone"):
		config["app"]["dialogue_tone"] = normalize_dialogue_tone(values["dialogue_tone"])
	if values.has("behavior_adaptation"):
		config["app"]["behavior_adaptation"] = normalize_behavior_adaptation(values["behavior_adaptation"])
	if values.has("ai_expression"):
		config["app"]["ai_expression"] = normalize_ai_expression(values["ai_expression"])
	if values.has("ai_memory_summary"):
		config["app"]["ai_memory_summary"] = normalize_ai_memory_summary(values["ai_memory_summary"])
	save_config()


func set_behavior_adaptation_config(values: Dictionary) -> void:
	set_app_config({"behavior_adaptation": values})


func set_ai_expression_config(values: Dictionary) -> void:
	set_app_config({"ai_expression": values})


func set_ai_memory_summary_config(values: Dictionary) -> void:
	set_app_config({"ai_memory_summary": values})


func set_dialogue_tone(value: String) -> void:
	set_app_config({"dialogue_tone": value})


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
		if source["app"].has("dialogue_tone"):
			merged["app"]["dialogue_tone"] = normalize_dialogue_tone(source["app"]["dialogue_tone"])
		if source["app"].has("behavior_adaptation"):
			merged["app"]["behavior_adaptation"] = normalize_behavior_adaptation(source["app"]["behavior_adaptation"])
		if source["app"].has("ai_expression"):
			merged["app"]["ai_expression"] = normalize_ai_expression(source["app"]["ai_expression"])
		if source["app"].has("ai_memory_summary"):
			merged["app"]["ai_memory_summary"] = normalize_ai_memory_summary(source["app"]["ai_memory_summary"])

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
