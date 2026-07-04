extends Node

const STORE_VERSION := 1
const FILE_NAME := "companion_profile.json"
const DEDUPE_LIMIT := 256
const SEVEN_DAYS := 7 * 24 * 60 * 60
const THIRTY_DAYS := 30 * 24 * 60 * 60
const USER_INTERACTION_KINDS := [
	"pet_head",
	"poke_body",
	"grab_start",
	"release_soft",
	"throw_fast",
	"peek_enter",
	"peek_exit",
	"feed_start",
	"feed_success",
	"tease_start",
	"tease_success",
]
const CARE_KINDS := ["feed_start", "feed_success", "auto_prompt"]
const PLAY_KINDS := ["tease_start", "tease_success"]
const DISRUPTIVE_KINDS := ["poke_body", "grab_start", "throw_fast", "auto_mischief"]

var profile_path := ""
var event_store = null
var memory_store = null
var data := _default_data()


func configure(config_dir: String, store = null, memory = null) -> void:
	profile_path = config_dir.path_join(FILE_NAME)
	event_store = store
	memory_store = memory
	_load_profile()
	refresh()


func refresh(now_unix := 0) -> void:
	var now = _coerce_now(now_unix)
	var previous = _sanitize_data(data)
	var lifetime = previous.get("lifetime", {}).duplicate(true)
	var processed_ids = _clean_string_array(lifetime.get("processed_event_ids", []))
	var processed_lookup := {}
	for event_id in processed_ids:
		processed_lookup[event_id] = true
	var events = _events_from_store()
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_id = _event_identity(event)
		if event_id == "" or processed_lookup.has(event_id):
			continue
		processed_lookup[event_id] = true
		processed_ids.append(event_id)
		_apply_lifetime_event(lifetime, event)
	while processed_ids.size() > DEDUPE_LIMIT:
		processed_lookup.erase(processed_ids.pop_front())
	lifetime["processed_event_ids"] = processed_ids

	var trends = _trend_snapshot(events, now)
	var memory = memory_store.snapshot() if memory_store != null and memory_store.has_method("snapshot") else {}
	data = _default_data()
	data["updated_at"] = now
	data["lifetime"] = _sanitize_lifetime(lifetime)
	data["trends"] = trends
	data["preferences"] = _derive_preferences(data["lifetime"], trends, memory)
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


func flush_save() -> void:
	if profile_path == "":
		return
	DirAccess.make_dir_recursive_absolute(profile_path.get_base_dir())
	var file = FileAccess.open(profile_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func _load_profile() -> void:
	data = _default_data()
	if profile_path == "" or not FileAccess.file_exists(profile_path):
		return
	var file = FileAccess.open(profile_path, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	data = _sanitize_data(parsed)


func _events_from_store() -> Array:
	if event_store == null:
		return []
	if event_store.has_method("all_events"):
		return event_store.all_events()
	if event_store.has_method("recent_events"):
		return event_store.recent_events(200)
	return []


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


func _apply_lifetime_event(lifetime: Dictionary, event: Dictionary) -> void:
	var kind = str(event.get("kind", "")).strip_edges()
	if kind == "":
		return
	lifetime["total_events"] = int(lifetime.get("total_events", 0)) + 1
	lifetime["last_event_at"] = max(int(lifetime.get("last_event_at", 0)), int(event.get("at", 0)))
	_increment(lifetime["counts"], kind)
	var mode = str(event.get("mode", "")).strip_edges()
	if mode != "":
		_increment(lifetime["mode_counts"], mode)
	var period = str(event.get("period", "")).strip_edges()
	if period != "":
		_increment(lifetime["period_counts"], period)
	if kind in CARE_KINDS:
		lifetime["care_score"] = int(lifetime.get("care_score", 0)) + 1
	if kind in PLAY_KINDS:
		lifetime["play_score"] = int(lifetime.get("play_score", 0)) + 1
	if kind in DISRUPTIVE_KINDS:
		lifetime["disruption_score"] = int(lifetime.get("disruption_score", 0)) + 1


func _trend_snapshot(events: Array, now: int) -> Dictionary:
	return {
		"7d": _window_from_events(events, now - SEVEN_DAYS, 7),
		"30d": _window_from_events(events, now - THIRTY_DAYS, 30),
	}


func _window_from_events(events: Array, cutoff: int, days: int) -> Dictionary:
	var result = _empty_window(days)
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var at = int(event.get("at", 0))
		if at < cutoff:
			continue
		var kind = str(event.get("kind", "")).strip_edges()
		if kind == "":
			continue
		result["total_events"] = int(result["total_events"]) + 1
		_increment(result["counts"], kind)
		if str(event.get("source", "")) == "user" and kind in USER_INTERACTION_KINDS:
			result["user_interactions"] = int(result["user_interactions"]) + 1
		var mode = str(event.get("mode", "")).strip_edges()
		if mode != "":
			_increment(result["mode_counts"], mode)
		var period = str(event.get("period", "")).strip_edges()
		if period != "":
			_increment(result["period_counts"], period)
	return result


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


func _event_identity(event: Dictionary) -> String:
	var event_id = str(event.get("id", "")).strip_edges()
	if event_id != "":
		return event_id
	var kind = str(event.get("kind", "")).strip_edges()
	if kind == "":
		return ""
	return "%s:%d:%s" % [kind, int(event.get("at", 0)), str(event.get("source", ""))]


func _increment(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key, 0)) + 1


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
