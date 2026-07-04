extends Node

const STORE_VERSION := 1
const FILE_NAME := "companion_memory.json"
const MAX_RECENT_LINES := 8
const SHORT_TERM_SECONDS := 3 * 24 * 60 * 60
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

var memory_path := ""
var event_store = null
var data := _default_data()


func configure(config_dir: String, store = null) -> void:
	memory_path = config_dir.path_join(FILE_NAME)
	event_store = store
	_load_memory()
	refresh()


func refresh(now_unix := 0) -> void:
	var now = _coerce_now(now_unix)
	var previous_dialogue = _sanitize_dialogue(data.get("dialogue", {}))
	var events = _events_from_store()
	var today = _date_for_unix(now)
	var short_term_cutoff = now - SHORT_TERM_SECONDS
	var daily_counts := {}
	var short_counts := {}
	var mode_counts := {}
	var period_counts := {}
	var interaction_counts := {}
	var recent_kinds := []
	var last_event_at := 0
	var last_event_kind := ""
	var user_interactions := 0
	var care_score := 0
	var play_score := 0

	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var kind = str(event.get("kind", "")).strip_edges()
		if kind == "":
			continue
		var at = int(event.get("at", 0))
		if at <= 0:
			at = now
		if at >= last_event_at:
			last_event_at = at
			last_event_kind = kind
		if _date_for_unix(at) == today:
			_increment(daily_counts, kind)
		if at >= short_term_cutoff:
			_increment(short_counts, kind)
			var mode = str(event.get("mode", "")).strip_edges()
			if mode != "":
				_increment(mode_counts, mode)
			var period = str(event.get("period", "")).strip_edges()
			if period != "":
				_increment(period_counts, period)
			recent_kinds.append(kind)
		if str(event.get("source", "")) == "user" and kind in USER_INTERACTION_KINDS:
			user_interactions += 1
			_increment(interaction_counts, kind)
		if kind in CARE_KINDS:
			care_score += 1
		if kind in PLAY_KINDS:
			play_score += 1

	var favorites = _top_keys(interaction_counts, 3)
	var familiarity = clampi(1 + user_interactions * 8 + care_score * 4 + play_score * 4, 1, 100)
	data = _default_data()
	data["updated_at"] = now
	data["daily"] = {
		"date": today,
		"counts": daily_counts,
		"last_event_at": last_event_at,
	}
	data["short_term"] = {
		"days": 3,
		"counts": short_counts,
		"mode_counts": mode_counts,
		"period_counts": period_counts,
		"recent_kinds": recent_kinds.slice(max(0, recent_kinds.size() - 12), recent_kinds.size()),
		"last_event_kind": last_event_kind,
	}
	data["preferences"] = {
		"favorite_interactions": favorites,
		"favorite_mode": _first_key(mode_counts),
		"favorite_period": _first_key(period_counts),
	}
	data["relationship"] = {
		"level": _relationship_level(familiarity),
		"familiarity": familiarity,
		"care_score": clampi(care_score * 10, 0, 100),
		"play_score": clampi(play_score * 10, 0, 100),
	}
	data["dialogue"] = previous_dialogue
	flush_save()


func snapshot() -> Dictionary:
	return data.duplicate(true)


func expression_context(extra := {}) -> Dictionary:
	var result := {
		"memory": snapshot(),
		"daily_counts": data.get("daily", {}).get("counts", {}),
		"short_term_counts": data.get("short_term", {}).get("counts", {}),
		"recent_kind": str(data.get("short_term", {}).get("last_event_kind", "")),
		"favorite_interactions": data.get("preferences", {}).get("favorite_interactions", []),
		"favorite_mode": str(data.get("preferences", {}).get("favorite_mode", "")),
		"favorite_period": str(data.get("preferences", {}).get("favorite_period", "")),
		"relationship": data.get("relationship", {}),
		"relationship_level": str(data.get("relationship", {}).get("level", "new")),
		"recent_expression_texts": _recent_expression_texts(),
	}
	if typeof(extra) == TYPE_DICTIONARY:
		for key in extra.keys():
			result[key] = extra[key]
	return result


func record_expression(key: String, text: String, now_unix := 0) -> void:
	var clean_text = text.strip_edges()
	if clean_text == "":
		return
	var dialogue = _sanitize_dialogue(data.get("dialogue", {}))
	var recent_lines = dialogue.get("recent_lines", [])
	recent_lines.append({
		"key": key.strip_edges(),
		"text": clean_text,
		"at": _coerce_now(now_unix),
	})
	while recent_lines.size() > MAX_RECENT_LINES:
		recent_lines.pop_front()
	dialogue["recent_lines"] = recent_lines
	data["dialogue"] = dialogue
	flush_save()


func flush_save() -> void:
	if memory_path == "":
		return
	DirAccess.make_dir_recursive_absolute(memory_path.get_base_dir())
	var file = FileAccess.open(memory_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func _load_memory() -> void:
	data = _default_data()
	if memory_path == "" or not FileAccess.file_exists(memory_path):
		return
	var file = FileAccess.open(memory_path, FileAccess.READ)
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
		"daily": {
			"date": "",
			"counts": {},
			"last_event_at": 0,
		},
		"short_term": {
			"days": 3,
			"counts": {},
			"mode_counts": {},
			"period_counts": {},
			"recent_kinds": [],
			"last_event_kind": "",
		},
		"preferences": {
			"favorite_interactions": [],
			"favorite_mode": "",
			"favorite_period": "",
		},
		"relationship": {
			"level": "new",
			"familiarity": 1,
			"care_score": 0,
			"play_score": 0,
		},
		"dialogue": {
			"recent_lines": [],
			"last_intent_at": {},
		},
	}


func _sanitize_data(value) -> Dictionary:
	var result = _default_data()
	if typeof(value) != TYPE_DICTIONARY:
		return result
	result["updated_at"] = max(0, int(value.get("updated_at", 0)))
	result["daily"] = _dictionary_or_default(value.get("daily", {}), result["daily"])
	result["short_term"] = _dictionary_or_default(value.get("short_term", {}), result["short_term"])
	result["preferences"] = _dictionary_or_default(value.get("preferences", {}), result["preferences"])
	result["relationship"] = _dictionary_or_default(value.get("relationship", {}), result["relationship"])
	result["dialogue"] = _sanitize_dialogue(value.get("dialogue", {}))
	return result


func _sanitize_dialogue(value) -> Dictionary:
	var result := {
		"recent_lines": [],
		"last_intent_at": {},
	}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	var recent = value.get("recent_lines", [])
	if typeof(recent) == TYPE_ARRAY:
		for item in recent:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var text = str(item.get("text", "")).strip_edges()
			if text == "":
				continue
			result["recent_lines"].append({
				"key": str(item.get("key", "")).strip_edges(),
				"text": text,
				"at": max(0, int(item.get("at", 0))),
			})
	while result["recent_lines"].size() > MAX_RECENT_LINES:
		result["recent_lines"].pop_front()
	var last_intent = value.get("last_intent_at", {})
	if typeof(last_intent) == TYPE_DICTIONARY:
		result["last_intent_at"] = last_intent.duplicate(true)
	return result


func _dictionary_or_default(value, default_value: Dictionary) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return default_value.duplicate(true)


func _increment(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


func _top_keys(counts: Dictionary, limit: int) -> Array:
	var keys = counts.keys()
	keys.sort_custom(func(a, b):
		var left = int(counts.get(a, 0))
		var right = int(counts.get(b, 0))
		if left == right:
			return str(a) < str(b)
		return left > right
	)
	return keys.slice(0, min(limit, keys.size()))


func _first_key(counts: Dictionary) -> String:
	var keys = _top_keys(counts, 1)
	return str(keys[0]) if keys.size() > 0 else ""


func _relationship_level(familiarity: int) -> String:
	if familiarity >= 70:
		return "close"
	if familiarity >= 25:
		return "familiar"
	return "new"


func _recent_expression_texts() -> Array:
	var result := []
	var dialogue = data.get("dialogue", {})
	if typeof(dialogue) != TYPE_DICTIONARY:
		return result
	var recent = dialogue.get("recent_lines", [])
	if typeof(recent) != TYPE_ARRAY:
		return result
	for item in recent:
		if typeof(item) == TYPE_DICTIONARY:
			var text = str(item.get("text", "")).strip_edges()
			if text != "":
				result.append(text)
	return result


func _date_for_unix(unix: int) -> String:
	var time = _local_datetime_from_unix(unix)
	return "%04d-%02d-%02d" % [int(time.get("year", 1970)), int(time.get("month", 1)), int(time.get("day", 1))]


func _local_datetime_from_unix(unix_time: int) -> Dictionary:
	var time_zone = Time.get_time_zone_from_system()
	var bias_minutes = int(time_zone.get("bias", 0)) if typeof(time_zone) == TYPE_DICTIONARY else 0
	return Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
