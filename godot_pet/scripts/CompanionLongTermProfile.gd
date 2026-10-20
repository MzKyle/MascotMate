extends Node

const STORE_VERSION := 1
const FILE_NAME := "companion_profile.json"
const DEDUPE_LIMIT := 256
const EventStore = preload("res://scripts/CompanionEventStore.gd")
const AtomicJson = preload("res://scripts/AtomicJson.gd")
const USER_INTERACTION_KINDS = EventStore.USER_INTERACTION_KINDS

var profile_path := ""
var event_store = null
var memory_store = null
var data := _default_data()


func configure(config_dir: String, store = null, memory = null) -> void:
	profile_path = config_dir.path_join(FILE_NAME)
	if event_store != null and event_store.event_recorded.is_connected(_on_event_recorded):
		event_store.event_recorded.disconnect(_on_event_recorded)
	event_store = store
	if event_store != null:
		event_store.event_recorded.connect(_on_event_recorded)
	memory_store = memory
	_load_profile()
	refresh()


func refresh(now_unix := 0) -> void:
	var now = _coerce_now(now_unix)
	var previous = _sanitize_data(data)
	var lifetime = event_store.aggregate(0, now) if event_store != null else EventStore.empty_summary()
	var ai_summary = _sanitize_ai_summary(previous.get("ai_summary", {}))
	var trends = {"7d": _aggregate_window(7, now), "30d": _aggregate_window(30, now)}

	var memory = memory_store.snapshot() if memory_store != null and memory_store.has_method("snapshot") else {}
	data = _default_data()
	data["updated_at"] = now
	data["lifetime"] = _sanitize_lifetime(lifetime)
	data["trends"] = trends
	data["preferences"] = _derive_preferences(data["lifetime"], trends, memory)
	data["ai_summary"] = ai_summary
	data["effective_preferences"] = _derive_effective_preferences(data["preferences"], ai_summary)
	data["relationship"] = _relationship_from_memory(memory)
	flush_save()


func snapshot() -> Dictionary:
	return data.duplicate(true)


func expression_context(extra := {}) -> Dictionary:
	var result := {
		"profile": snapshot(),
		"long_term_preferences": data.get("preferences", {}),
		"profile_relationship": data.get("relationship", {}),
		"profile_trends": data.get("trends", {}),
	}
	if typeof(extra) == TYPE_DICTIONARY:
		for key in extra.keys():
			result[key] = extra[key]
	return result


func apply_ai_summary(summary: Dictionary, now_unix := 0) -> bool:
	var sanitized = _sanitize_ai_summary(summary)
	if sanitized.is_empty():
		return false
	data = _sanitize_data(data)
	sanitized["updated_at"] = _coerce_now(now_unix)
	data["ai_summary"] = sanitized
	data["effective_preferences"] = _derive_effective_preferences(data.get("preferences", {}), sanitized)
	flush_save()
	return true


func _on_event_recorded(event: Dictionary) -> void:
	refresh(int(event.get("at", 0)))


func _aggregate_window(days: int, now: int) -> Dictionary:
	var result = event_store.aggregate(days, now) if event_store != null else EventStore.empty_summary()
	return _sanitize_window(result, days)


func flush_save() -> void:
	if profile_path != "":
		AtomicJson.write_dictionary(profile_path, data)


func _load_profile() -> void:
	data = _sanitize_data(AtomicJson.read_dictionary(profile_path))


func _default_data() -> Dictionary:
	return {
		"version": STORE_VERSION,
		"updated_at": 0,
		"lifetime": {
			"total_events": 0,
			"counts": {},
			"mode_counts": {},
			"period_counts": {},
			"care_score": 0,
			"play_score": 0,
			"disruption_score": 0,
			"last_event_at": 0,
			"processed_event_ids": [],
		},
		"trends": {
			"7d": _empty_window(7),
			"30d": _empty_window(30),
		},
		"preferences": {
			"favorite_interactions": [],
			"favorite_mode": "",
			"favorite_period": "",
			"care_tendency": 0,
			"play_tendency": 0,
			"interruption_tolerance": "medium",
		},
		"ai_summary": {},
		"effective_preferences": {
			"favorite_interactions": [],
			"favorite_mode": "",
			"favorite_period": "",
			"care_tendency": 0,
			"play_tendency": 0,
			"interruption_tolerance": "medium",
		},
		"relationship": {
			"level": "new",
			"familiarity": 1,
			"care_score": 0,
			"play_score": 0,
		},
	}


func _empty_window(days: int) -> Dictionary:
	return {
		"days": days,
		"counts": {},
		"mode_counts": {},
		"period_counts": {},
		"total_events": 0,
		"user_interactions": 0,
	}


func _sanitize_data(value) -> Dictionary:
	var result = _default_data()
	if typeof(value) != TYPE_DICTIONARY:
		return result
	result["updated_at"] = max(0, int(value.get("updated_at", 0)))
	result["lifetime"] = _sanitize_lifetime(value.get("lifetime", {}))
	var trends = value.get("trends", {})
	if typeof(trends) == TYPE_DICTIONARY:
		result["trends"]["7d"] = _sanitize_window(trends.get("7d", {}), 7)
		result["trends"]["30d"] = _sanitize_window(trends.get("30d", {}), 30)
	result["preferences"] = _dictionary_or_default(value.get("preferences", {}), result["preferences"])
	result["ai_summary"] = _sanitize_ai_summary(value.get("ai_summary", {}))
	result["effective_preferences"] = _derive_effective_preferences(result["preferences"], result["ai_summary"])
	result["relationship"] = _dictionary_or_default(value.get("relationship", {}), result["relationship"])
	return result


func _sanitize_lifetime(value) -> Dictionary:
	var result = _default_data()["lifetime"].duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return result
	result["total_events"] = max(0, int(value.get("total_events", 0)))
	result["counts"] = _clean_count_dict(value.get("counts", {}))
	result["mode_counts"] = _clean_count_dict(value.get("mode_counts", {}))
	result["period_counts"] = _clean_count_dict(value.get("period_counts", {}))
	result["care_score"] = max(0, int(value.get("care_score", 0)))
	result["play_score"] = max(0, int(value.get("play_score", 0)))
	result["disruption_score"] = max(0, int(value.get("disruption_score", 0)))
	result["last_event_at"] = max(0, int(value.get("last_event_at", 0)))
	result["processed_event_ids"] = _clean_string_array(value.get("processed_event_ids", [])).slice(0, DEDUPE_LIMIT)
	return result


func _sanitize_window(value, days: int) -> Dictionary:
	var result = _empty_window(days)
	if typeof(value) != TYPE_DICTIONARY:
		return result
	result["counts"] = _clean_count_dict(value.get("counts", {}))
	result["mode_counts"] = _clean_count_dict(value.get("mode_counts", {}))
	result["period_counts"] = _clean_count_dict(value.get("period_counts", {}))
	result["total_events"] = max(0, int(value.get("total_events", 0)))
	result["user_interactions"] = max(0, int(value.get("user_interactions", 0)))
	return result


func _dictionary_or_default(value, fallback: Dictionary) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var result = fallback.duplicate(true)
		for key in value.keys():
			result[key] = value[key]
		return result
	return fallback.duplicate(true)


func _derive_preferences(lifetime: Dictionary, trends: Dictionary, memory: Dictionary) -> Dictionary:
	var counts = lifetime.get("counts", {})
	var favorite_interactions := []
	for key in USER_INTERACTION_KINDS:
		if int(counts.get(key, 0)) > 0:
			favorite_interactions.append({"key": key, "count": int(counts.get(key, 0))})
	favorite_interactions.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	var favorites := []
	for item in favorite_interactions.slice(0, min(3, favorite_interactions.size())):
		favorites.append(str(item["key"]))
	var memory_preferences = memory.get("preferences", {}) if typeof(memory) == TYPE_DICTIONARY else {}
	if typeof(memory_preferences) == TYPE_DICTIONARY:
		for key in _clean_string_array(memory_preferences.get("favorite_interactions", [])):
			if not favorites.has(key):
				favorites.append(key)
			if favorites.size() >= 3:
				break
	var care_score = int(lifetime.get("care_score", 0))
	var play_score = int(lifetime.get("play_score", 0))
	var total = max(1, int(lifetime.get("total_events", 0)))
	return {
		"favorite_interactions": favorites,
		"favorite_mode": _first_key(lifetime.get("mode_counts", {})),
		"favorite_period": _first_key(lifetime.get("period_counts", {})),
		"care_tendency": clampi(int(round(float(care_score) / float(total) * 100.0)), 0, 100),
		"play_tendency": clampi(int(round(float(play_score) / float(total) * 100.0)), 0, 100),
		"interruption_tolerance": _interruption_tolerance(lifetime, trends),
	}


func _derive_effective_preferences(local_preferences: Dictionary, ai_summary: Dictionary) -> Dictionary:
	var local = _dictionary_or_default(local_preferences, _default_data()["preferences"])
	var result = local.duplicate(true)
	if ai_summary.is_empty() or int(ai_summary.get("confidence", 0)) < 60:
		return _sanitize_preferences(result)
	var local_favorites = _clean_string_array(local.get("favorite_interactions", []))
	var ai_favorites = _clean_string_array(ai_summary.get("favorite_interactions", []))
	for key in ai_favorites:
		if not key in local_favorites:
			local_favorites.append(key)
		if local_favorites.size() >= 3:
			break
	result["favorite_interactions"] = local_favorites.slice(0, min(3, local_favorites.size()))
	if str(result.get("favorite_mode", "")) == "":
		result["favorite_mode"] = str(ai_summary.get("favorite_mode", ""))
	if str(result.get("favorite_period", "")) == "":
		result["favorite_period"] = str(ai_summary.get("favorite_period", ""))
	result["care_tendency"] = _soft_numeric(int(local.get("care_tendency", 0)), int(ai_summary.get("care_tendency", 0)))
	result["play_tendency"] = _soft_numeric(int(local.get("play_tendency", 0)), int(ai_summary.get("play_tendency", 0)))
	var local_interrupt = str(local.get("interruption_tolerance", "medium"))
	var ai_interrupt = str(ai_summary.get("interruption_tolerance", "medium"))
	if local_interrupt == "medium" and int(ai_summary.get("confidence", 0)) >= 80:
		result["interruption_tolerance"] = ai_interrupt
	return _sanitize_preferences(result)


func _sanitize_preferences(value) -> Dictionary:
	var fallback = _default_data()["preferences"]
	var result = fallback.duplicate(true)
	if typeof(value) != TYPE_DICTIONARY:
		return result
	result["favorite_interactions"] = _clean_string_array(value.get("favorite_interactions", [])).slice(0, 3)
	var mode = str(value.get("favorite_mode", "")).strip_edges()
	result["favorite_mode"] = mode if mode in ["", "安静", "活泼", "捣乱"] else ""
	var period = str(value.get("favorite_period", "")).strip_edges()
	result["favorite_period"] = period if period in ["", "work", "entertainment", "rest"] else ""
	result["care_tendency"] = clampi(int(value.get("care_tendency", 0)), 0, 100)
	result["play_tendency"] = clampi(int(value.get("play_tendency", 0)), 0, 100)
	var interruption = str(value.get("interruption_tolerance", "medium")).strip_edges()
	result["interruption_tolerance"] = interruption if interruption in ["low", "medium", "high"] else "medium"
	return result


func _sanitize_ai_summary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var confidence = clampi(int(value.get("confidence", 0)), 0, 100)
	if confidence < 60:
		return {}
	var result = _sanitize_preferences(value)
	result["confidence"] = confidence
	result["updated_at"] = max(0, int(value.get("updated_at", value.get("at", 0))))
	return result


func _soft_numeric(local_value: int, ai_value: int) -> int:
	var delta = clampi(ai_value - local_value, -10, 10)
	return clampi(local_value + delta, 0, 100)


func _relationship_from_memory(memory: Dictionary) -> Dictionary:
	if typeof(memory) != TYPE_DICTIONARY:
		return _default_data()["relationship"].duplicate(true)
	var relationship = memory.get("relationship", {})
	if typeof(relationship) != TYPE_DICTIONARY:
		return _default_data()["relationship"].duplicate(true)
	return {
		"level": str(relationship.get("level", "new")),
		"familiarity": clampi(int(relationship.get("familiarity", 1)), 1, 100),
		"care_score": clampi(int(relationship.get("care_score", 0)), 0, 100),
		"play_score": clampi(int(relationship.get("play_score", 0)), 0, 100),
	}


func _interruption_tolerance(lifetime: Dictionary, trends: Dictionary) -> String:
	var counts = lifetime.get("counts", {})
	var positive = int(counts.get("pet_head", 0)) + int(counts.get("feed_success", 0)) + int(counts.get("tease_success", 0))
	var disruption = int(lifetime.get("disruption_score", 0))
	var active_mode = int(lifetime.get("mode_counts", {}).get("活泼", 0))
	var quiet_mode = int(lifetime.get("mode_counts", {}).get("安静", 0))
	var recent_user = int(trends.get("7d", {}).get("user_interactions", 0))
	if quiet_mode > active_mode * 2 and recent_user <= 2:
		return "low"
	if positive + disruption >= 8 or active_mode > quiet_mode * 2:
		return "high"
	return "medium"


func _first_key(counts) -> String:
	if typeof(counts) != TYPE_DICTIONARY:
		return ""
	var best_key := ""
	var best_count := -1
	for key in counts.keys():
		var count = int(counts[key])
		if count > best_count:
			best_key = str(key)
			best_count = count
	return best_key


func _clean_count_dict(value) -> Dictionary:
	var result := {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		var clean_key = str(key).strip_edges()
		var count = max(0, int(value[key]))
		if clean_key != "" and count > 0:
			result[clean_key] = count
	return result


func _clean_string_array(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		var text = str(item).strip_edges()
		if text != "":
			result.append(text)
	return result


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
