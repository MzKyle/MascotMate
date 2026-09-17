extends RefCounted

const FIXED_ENTERTAINMENT_TIME := 1761998400
const FIXED_WORK_TIME := 1762164000
const FIXED_REST_TIME := 1762038000


static func repo_root() -> String:
	return ProjectSettings.globalize_path("res://..").simplify_path()


static func config_dir() -> String:
	var value = OS.get_environment("CRAYON_PET_CONFIG_DIR").strip_edges()
	if value != "":
		DirAccess.make_dir_recursive_absolute(value)
	return value


static func calm_state(now_unix: int) -> Dictionary:
	return {
		"version": 2,
		"mood": 70,
		"hunger": 60,
		"energy": 80,
		"affection": 30,
		"last_decay_at": now_unix,
		"memory": {
			"last_interaction_at": 0,
			"last_interaction_kind": "",
			"last_feed_at": 0,
			"last_play_at": 0,
			"last_prompt_at": 0,
			"last_action_at": 0,
			"interaction_counts": {},
		},
	}


static func adaptive_memory(favorites: Array, familiarity: int, care_score: int, play_score: int) -> Dictionary:
	return {
		"version": 1,
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": "活泼",
			"favorite_period": "entertainment",
		},
		"relationship": {
			"level": "close" if familiarity >= 70 else "familiar",
			"familiarity": familiarity,
			"care_score": care_score,
			"play_score": play_score,
		},
		"short_term": {
			"counts": {},
			"recent_kinds": favorites,
		},
	}


static func adaptive_profile(care_tendency: int, play_tendency: int, interruption_tolerance: String, favorite_mode := "活泼", favorite_period := "entertainment", favorites := []) -> Dictionary:
	return {
		"version": 1,
		"updated_at": 0,
		"lifetime": {
			"total_events": 0,
			"counts": {},
			"mode_counts": {},
			"period_counts": {},
			"care_score": care_tendency,
			"play_score": play_tendency,
			"disruption_score": 0,
			"last_event_at": 0,
			"processed_event_ids": [],
		},
		"trends": {},
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": favorite_mode,
			"favorite_period": favorite_period,
			"care_tendency": care_tendency,
			"play_tendency": play_tendency,
			"interruption_tolerance": interruption_tolerance,
		},
		"relationship": {
			"level": "familiar",
			"familiarity": 45,
			"care_score": care_tendency,
			"play_score": play_tendency,
		},
	}


static func decision_has_profile_reason(decision: Dictionary) -> bool:
	var adaptation = decision.get("adaptation", {})
	if typeof(adaptation) != TYPE_DICTIONARY:
		return false
	var reasons = adaptation.get("reasons", [])
	if typeof(reasons) != TYPE_ARRAY:
		return false
	for reason in reasons:
		if str(reason).find("profile") >= 0:
			return true
	return false


static func adaptive_personality(playfulness: int, mischief: int, patience: int, clinginess: int) -> Dictionary:
	return {
		"version": 1,
		"archetype": "playful",
		"tone": "short_cute",
		"traits": {
			"playfulness": playfulness,
			"mischief": mischief,
			"patience": patience,
			"clinginess": clinginess,
		},
		"dialogue_style": {
			"max_chars": 28,
			"use_status_numbers": false,
			"avoid_repeating_recent": true,
		},
	}


static func unix_for_local_datetime(year: int, month: int, day: int, hour: int) -> int:
	var utc_unix = int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": 0,
		"second": 0,
	}))
	var time_zone = Time.get_time_zone_from_system()
	var bias_minutes = int(time_zone.get("bias", 0)) if typeof(time_zone) == TYPE_DICTIONARY else 0
	return utc_unix - bias_minutes * 60


static func load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing JSON: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON: %s" % path)
		return {}
	return parsed
