extends Node

# Emitted only when the active configuration changes. Setters return the save result.
signal config_changed(config)

const AtomicJson = preload("res://scripts/AtomicJson.gd")

const DEFAULT_CONFIG := {
	"version": 1,
	"app": {
		"display_scale": 1.0,
		"gravity_enabled": true,
		"skin_id": "classic_shinchan",
		"dialogue_tone": "gentle",
		"onboarding_version": 0,
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
var _load_error: Error = OK
var _needs_save := false


func configure() -> Error:
	config_dir = _config_dir()
	config_path = config_dir.path_join("config.json")
	return load_config()


func load_config() -> Error:
	config = DEFAULT_CONFIG.duplicate(true)
	var loaded := AtomicJson.load_dictionary(config_path, _valid_config)
	var error: Error = loaded["error"]
	var primary_error: Error = loaded["primary_error"]
	# If access returns later, avoid overwriting data we never got to read.
	_load_error = primary_error if not AtomicJson.can_replace(primary_error) else OK
	if not AtomicJson.can_replace(error):
		_load_error = error
	_needs_save = primary_error != OK
	if error == OK:
		config = _merged_config(loaded["data"])
		if _needs_save and _load_error == OK:
			return save_config()
	elif error == ERR_FILE_NOT_FOUND:
		return save_config()
	return error if _load_error == OK else _load_error


func save_config() -> Error:
	return _write_config(config)


func _write_config(next: Dictionary) -> Error:
	var error := _load_error
	if error == OK:
		error = AtomicJson.write_dictionary(config_path, next, _valid_config, true)
	if error != OK:
		push_warning("Could not save %s: %s" % [config_path, error_string(error)])
	else:
		_needs_save = false
	return error


func get_config() -> Dictionary:
	return config.duplicate(true)


func app_config() -> Dictionary:
	return config.get("app", {}).duplicate(true)


func normalize_dialogue_tone(value) -> String:
	var tone = str(value).strip_edges()
	return tone if tone in ["gentle", "short_cute", "calm"] else "gentle"


func normalize_onboarding_version(value) -> int:
	return max(0, int(value))


func normalize_behavior_adaptation(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["behavior_adaptation"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	merged.merge(value, true)
	var strength = str(merged["strength"])
	merged["strength"] = strength if strength in ["subtle", "visible", "bold"] else "visible"
	merged["enabled"] = bool(merged["enabled"])
	return merged


func normalize_ai_expression(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["ai_expression"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	merged.merge(value, true)
	var provider = str(merged["provider"])
	merged["provider"] = provider if provider in ["local_stub", "openai_compatible"] else "local_stub"
	merged["enabled"] = bool(merged["enabled"])
	merged["timeout_ms"] = clampi(int(merged["timeout_ms"]), 100, 5000)
	return merged


func normalize_ai_memory_summary(value) -> Dictionary:
	var merged = DEFAULT_CONFIG["app"]["ai_memory_summary"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return merged
	merged.merge(value, true)
	var provider = str(merged["provider"])
	merged["provider"] = provider if provider in ["local_stub", "openai_compatible"] else "local_stub"
	merged["enabled"] = bool(merged["enabled"])
	merged["timeout_ms"] = clampi(int(merged["timeout_ms"]), 100, 5000)
	merged["min_events"] = clampi(int(merged["min_events"]), 1, 200)
	merged["min_interval_seconds"] = clampi(int(merged["min_interval_seconds"]), 60, 30 * 24 * 60 * 60)
	return merged


func screenshot_pins_config() -> Dictionary:
	return {
		"shortcuts": config.get("shortcuts", {}).duplicate(true),
		"screenshot": config.get("screenshot", {}).duplicate(true),
		"pins": config.get("pins", {}).duplicate(true),
	}


func onboarding_version() -> int:
	return normalize_onboarding_version(app_config().get("onboarding_version", 0))


func set_app_config(values: Dictionary) -> Error:
	return _set_config({"app": values})


func set_behavior_adaptation_config(values: Dictionary) -> Error:
	return set_app_config({"behavior_adaptation": values})


func set_ai_expression_config(values: Dictionary) -> Error:
	return set_app_config({"ai_expression": values})


func set_ai_memory_summary_config(values: Dictionary) -> Error:
	return set_app_config({"ai_memory_summary": values})


func set_dialogue_tone(value: String) -> Error:
	return set_app_config({"dialogue_tone": value})


func set_onboarding_version(value: int) -> Error:
	return set_app_config({"onboarding_version": value})


func set_screenshot_pins_config(values: Dictionary) -> Error:
	return _set_config(values)


func _set_config(values: Dictionary) -> Error:
	if not _matches_schema(values, DEFAULT_CONFIG):
		return ERR_INVALID_DATA
	var next := _merged_config(_merge_settings(config, values))
	var changed := next != config
	if not changed and not _needs_save:
		return OK
	var error := _write_config(next)
	if error == OK and changed:
		config = next
		config_changed.emit(get_config())
	return error


func _merge_settings(base: Dictionary, values: Dictionary) -> Dictionary:
	var merged = base.duplicate(true)
	var overrides := values.duplicate(true)
	for key in values.keys():
		if typeof(merged.get(key)) == TYPE_DICTIONARY and typeof(values[key]) == TYPE_DICTIONARY:
			merged[key] = _merge_settings(merged[key], values[key])
		else:
			merged[key] = overrides[key]
	return merged


func _merged_config(source: Dictionary) -> Dictionary:
	var merged := _merge_settings(DEFAULT_CONFIG, source)
	merged["version"] = maxi(1, int(merged["version"]))
	var app: Dictionary = merged["app"]
	app["display_scale"] = clampf(float(app["display_scale"]), 1.0, 1.5)
	var skin_id: String = app["skin_id"].strip_edges()
	app["skin_id"] = skin_id if skin_id != "" else "classic_shinchan"
	app["dialogue_tone"] = normalize_dialogue_tone(app["dialogue_tone"])
	app["onboarding_version"] = normalize_onboarding_version(app["onboarding_version"])
	app["behavior_adaptation"] = normalize_behavior_adaptation(app["behavior_adaptation"])
	app["ai_expression"] = normalize_ai_expression(app["ai_expression"])
	app["ai_memory_summary"] = normalize_ai_memory_summary(app["ai_memory_summary"])
	var backend: String = merged["screenshot"]["backend"]
	merged["screenshot"]["backend"] = backend if backend in ["auto", "godot", "spectacle", "import"] else "auto"
	merged["pins"]["max_count"] = clampi(int(merged["pins"]["max_count"]), 1, 3)
	return merged


func _valid_config(value: Dictionary) -> bool:
	var version = value.get("version", 1)
	return AtomicJson.is_number(version, true) and float(version) >= 0.0 and _matches_schema(value, DEFAULT_CONFIG)


func _matches_schema(values: Dictionary, defaults: Dictionary) -> bool:
	for key in defaults:
		if not values.has(key):
			continue
		var value = values[key]
		match typeof(defaults[key]):
			TYPE_DICTIONARY:
				if typeof(value) != TYPE_DICTIONARY or not _matches_schema(value, defaults[key]):
					return false
			TYPE_INT, TYPE_FLOAT:
				if not AtomicJson.is_number(value):
					return false
			_:
				if typeof(value) != typeof(defaults[key]):
					return false
	return true


func _config_dir() -> String:
	return preload("res://scripts/AppPaths.gd").data_dir()
