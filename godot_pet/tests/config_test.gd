extends SceneTree

const ConfigStoreScript = preload("res://scripts/ConfigStore.gd")
const TestSupport = preload("res://tests/TestSupport.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var config_dir = TestSupport.config_dir()
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for config tests.")
		return

	var config_store = ConfigStoreScript.new()
	root_node.add_child(config_store)
	config_store.configure()
	for tone in ["gentle", "short_cute", "calm"]:
		if config_store.normalize_dialogue_tone(tone) != tone:
			_fail("ConfigStore rejected valid dialogue tone: %s" % tone)
			return
	if config_store.normalize_dialogue_tone("loud") != "gentle":
		_fail("ConfigStore did not fallback invalid dialogue tone.")
		return
	var normalized_adaptation = config_store.normalize_behavior_adaptation({"enabled": false, "strength": "loud"})
	if bool(normalized_adaptation.get("enabled", true)) or str(normalized_adaptation.get("strength", "")) != "visible":
		_fail("ConfigStore did not normalize behavior adaptation fallback: %s" % JSON.stringify(normalized_adaptation))
		return
	normalized_adaptation = config_store.normalize_behavior_adaptation({"enabled": true, "strength": "bold"})
	if not bool(normalized_adaptation.get("enabled", false)) or str(normalized_adaptation.get("strength", "")) != "bold":
		_fail("ConfigStore did not preserve valid behavior adaptation: %s" % JSON.stringify(normalized_adaptation))
		return
	var ai_before_normalize = config_store.app_config().get("ai_expression", {})
	var normalized_ai = config_store.normalize_ai_expression({"enabled": true, "provider": "openai_compatible", "timeout_ms": 1200})
	if not bool(normalized_ai.get("enabled", false)) or str(normalized_ai.get("provider", "")) != "openai_compatible" or int(normalized_ai.get("timeout_ms", 0)) != 1200:
		_fail("ConfigStore did not preserve valid AI expression config: %s" % JSON.stringify(normalized_ai))
		return
	var ai_after_normalize = config_store.app_config().get("ai_expression", {})
	if bool(ai_after_normalize.get("enabled", false)) != bool(ai_before_normalize.get("enabled", false)) or int(ai_after_normalize.get("timeout_ms", 0)) != int(ai_before_normalize.get("timeout_ms", 0)):
		_fail("ConfigStore normalize_ai_expression unexpectedly persisted config: before=%s after=%s" % [JSON.stringify(ai_before_normalize), JSON.stringify(ai_after_normalize)])
		return
	normalized_ai = config_store.normalize_ai_expression({"provider": "bad", "timeout_ms": 1})
	if str(normalized_ai.get("provider", "")) != "local_stub" or int(normalized_ai.get("timeout_ms", 0)) != 100:
		_fail("ConfigStore did not clamp/fallback low AI expression config: %s" % JSON.stringify(normalized_ai))
		return
	normalized_ai = config_store.normalize_ai_expression({"timeout_ms": 999999})
	if int(normalized_ai.get("timeout_ms", 0)) != 5000:
		_fail("ConfigStore did not clamp high AI expression timeout: %s" % JSON.stringify(normalized_ai))
		return
	var normalized_summary = config_store.normalize_ai_memory_summary({
		"enabled": true,
		"provider": "openai_compatible",
		"timeout_ms": 1600,
		"min_events": 20,
		"min_interval_seconds": 900,
	})
	if not bool(normalized_summary.get("enabled", false)) or str(normalized_summary.get("provider", "")) != "openai_compatible" or int(normalized_summary.get("timeout_ms", 0)) != 1600 or int(normalized_summary.get("min_events", 0)) != 20 or int(normalized_summary.get("min_interval_seconds", 0)) != 900:
		_fail("ConfigStore did not preserve valid AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	normalized_summary = config_store.normalize_ai_memory_summary({
		"provider": "bad",
		"timeout_ms": 1,
		"min_events": 0,
		"min_interval_seconds": 1,
	})
	if str(normalized_summary.get("provider", "")) != "local_stub" or int(normalized_summary.get("timeout_ms", 0)) != 100 or int(normalized_summary.get("min_events", 0)) != 1 or int(normalized_summary.get("min_interval_seconds", 0)) != 60:
		_fail("ConfigStore did not clamp/fallback low AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	normalized_summary = config_store.normalize_ai_memory_summary({
		"timeout_ms": 999999,
		"min_events": 999,
		"min_interval_seconds": 999999999,
	})
	if int(normalized_summary.get("timeout_ms", 0)) != 5000 or int(normalized_summary.get("min_events", 0)) != 200 or int(normalized_summary.get("min_interval_seconds", 0)) != 30 * 24 * 60 * 60:
		_fail("ConfigStore did not clamp high AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	config_store.set_behavior_adaptation_config({"enabled": false, "strength": "bold"})
	var adaptation_config = config_store.app_config().get("behavior_adaptation", {})
	if bool(adaptation_config.get("enabled", true)) or str(adaptation_config.get("strength", "")) != "bold":
		_fail("ConfigStore did not persist behavior adaptation config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_dialogue_tone("calm")
	if str(config_store.app_config().get("dialogue_tone", "")) != "calm":
		_fail("ConfigStore did not persist dialogue tone config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_ai_expression_config({"enabled": true, "provider": "local_stub", "timeout_ms": 1200})
	var ai_config = config_store.app_config().get("ai_expression", {})
	if not bool(ai_config.get("enabled", false)) or str(ai_config.get("provider", "")) != "local_stub" or int(ai_config.get("timeout_ms", 0)) != 1200:
		_fail("ConfigStore did not persist AI expression config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_ai_memory_summary_config({"enabled": true, "provider": "local_stub", "timeout_ms": 1500, "min_events": 5, "min_interval_seconds": 600})
	var summary_config = config_store.app_config().get("ai_memory_summary", {})
	if not bool(summary_config.get("enabled", false)) or int(summary_config.get("min_events", 0)) != 5 or int(summary_config.get("min_interval_seconds", 0)) != 600:
		_fail("ConfigStore did not persist AI memory summary config: %s" % JSON.stringify(config_store.get_config()))
		return

	print("Godot config test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
