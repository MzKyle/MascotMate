extends RefCounted

const ScenarioRunner = preload("res://scripts/CompanionScenarioRunner.gd")


static func execute(app, request: Dictionary) -> Dictionary:
	var payload: Dictionary = request.get("payload", {})
	match request.get("command"):
		"select_skin":
			if app.skin_manager == null:
				return _saved(ERR_UNCONFIGURED)
			app.skin_manager.reload_skins()
			return _saved(app._set_skin(str(payload.get("skin_id", ""))))
		"set_behavior_mode":
			var mode = payload.get("mode")
			if mode not in ["安静", "活泼", "捣乱"]:
				return {"ok": false, "error": "invalid_mode"}
			app._set_behavior_mode(mode, false)
			return {"ok": true}
		"set_dialogue_tone":
			return _saved(app._set_dialogue_tone(str(payload.get("tone", "")), false))
		"set_adaptation":
			return _saved(app._set_behavior_adaptation(payload))
		"set_ai_expression":
			return _saved(app._set_ai_expression_config(payload))
		"set_ai_memory_summary":
			return _saved(app._set_ai_memory_summary_config(payload))
		"check_ai_health":
			return await _check_ai_health(app)
		"summarize_memory":
			var summary: Dictionary = await app._maybe_summarize_memory(true)
			return {"ok": summary.get("source") == "ai", "error": str(summary.get("fallback_reason", "summary_failed"))}
		"rebuild_memory":
			if app.companion_memory == null or app.companion_profile == null:
				return _saved(ERR_UNCONFIGURED)
			var memory_error: Error = app.companion_memory.refresh()
			var profile_error: Error = app.companion_profile.refresh()
			app._write_companion_debug_snapshot()
			return _saved(memory_error if memory_error != OK else profile_error)
		"run_scenario":
			var scenario: String = str(payload.get("scenario_id", "all"))
			if scenario != "all" and scenario not in ScenarioRunner.AVAILABLE_SCENARIOS:
				return {"ok": false, "error": "invalid_scenario"}
			var result: Dictionary = app._run_companion_scenarios(scenario)
			return _saved(result.get("save_error", OK))
		_:
			return {"ok": false, "error": "unknown_command"}


static func _check_ai_health(app) -> Dictionary:
	if app.companion_ai_expression_client == null:
		return _saved(ERR_UNCONFIGURED)
	var health: Dictionary = await app.companion_ai_expression_client.check_health()
	app._write_companion_debug_snapshot()
	return {
		"ok": bool(health.get("ok", false)) and bool(health.get("configured", false)),
		"error": str(health.get("status", "health_failed")),
	}


static func _saved(error: Error) -> Dictionary:
	return {"ok": error == OK, "error": error_string(error)}
