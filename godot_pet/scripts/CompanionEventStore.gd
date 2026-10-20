extends Node

signal event_recorded(event)

const STORE_VERSION := 2
const MAX_EVENTS := 200
const FILE_NAME := "companion_events.json"
const AtomicJson = preload("res://scripts/AtomicJson.gd")
const USER_INTERACTION_KINDS := ["pet_head", "poke_body", "grab_start", "release_soft", "throw_fast", "peek_enter", "peek_exit", "feed_start", "feed_success", "tease_start", "tease_success"]
const CARE_KINDS := ["feed_start", "feed_success", "auto_prompt"]
const PLAY_KINDS := ["tease_start", "tease_success"]
const DISRUPTIVE_KINDS := ["poke_body", "grab_start", "throw_fast", "auto_mischief"]
const COUNT_FIELDS := ["counts", "mode_counts", "period_counts", "interaction_counts"]
const TOTAL_FIELDS := ["total_events", "user_interactions", "care_score", "play_score", "disruption_score"]

var event_path := ""
var data := _default_data()
var last_save_error: Error = OK


func configure(config_dir: String) -> void:
	event_path = config_dir.path_join(FILE_NAME)
	_load_events()


func record_event(kind: String, source := "system", context := {}, meta := {}, tags := [], state_before := {}, state_after := {}, now_unix := 0) -> Dictionary:
	var clean_kind = kind.strip_edges()
	if clean_kind == "":
		return {}
	var now = _coerce_now(now_unix)
	var sequence = max(1, int(data.get("next_sequence", 1)))
	var event_context = context if typeof(context) == TYPE_DICTIONARY else {}
	var before = _dictionary_or_empty(state_before)
	if before.is_empty():
		before = _dictionary_or_empty(event_context.get("state", {}))
	var after = _dictionary_or_empty(state_after)
	if after.is_empty():
		after = before.duplicate(true)
	var event := {
		"version": STORE_VERSION,
		"id": "evt_%d_%04d" % [now, sequence],
		"at": now,
		"date": date_for_unix(now),
		"source": str(source),
		"kind": clean_kind,
		"period": str(event_context.get("period", "")),
		"mode": str(event_context.get("mode", "")),
		"skin_id": str(event_context.get("skin_id", "")),
		"state_before": before,
		"state_after": after,
		"tags": _clean_string_array(tags),
		"meta": _dictionary_or_empty(meta),
	}
	var date = str(event["date"])
	var bucket = data["daily"].get(date, empty_summary())
	_apply_event(bucket, event)
	data["daily"][date] = bucket
	data["events"].append(event)
	data["events"] = _trim_events(data["events"])
	data["next_sequence"] = sequence + 1
	flush_save()
	event_recorded.emit(event.duplicate(true))
	return event


func recent_events(limit := 20) -> Array:
	var events: Array = data["events"]
	var clean_limit = clampi(int(limit), 0, MAX_EVENTS)
	return events.slice(max(0, events.size() - clean_limit)).duplicate(true) if clean_limit > 0 else []


func all_events() -> Array:
	return data["events"].duplicate(true)


# days=0 returns all recorded days. Calendar dates are fixed when events arrive.
func aggregate(days := 0, now_unix := 0) -> Dictionary:
	var result = empty_summary()
	var today = date_for_unix(_coerce_now(now_unix))
	var today_day = int(Time.get_unix_time_from_datetime_string(today + "T00:00:00") / 86400)
	for date in data["daily"]:
		var day = int(Time.get_unix_time_from_datetime_string(str(date) + "T00:00:00") / 86400)
		if days > 0 and (day > today_day or day < today_day - days + 1):
			continue
		var bucket: Dictionary = data["daily"][date]
		for field in COUNT_FIELDS:
			for key in bucket[field]:
				result[field][key] = int(result[field].get(key, 0)) + int(bucket[field][key])
		for field in TOTAL_FIELDS:
			result[field] += int(bucket[field])
		if int(bucket["last_event_at"]) >= int(result["last_event_at"]):
			result["last_event_at"] = int(bucket["last_event_at"])
			result["last_event_kind"] = str(bucket["last_event_kind"])
	return result


func flush_save() -> Error:
	last_save_error = AtomicJson.write_dictionary(event_path, data, _valid_store)
	return last_save_error


func _load_events() -> void:
	data = _default_data()
	var parsed = AtomicJson.read_dictionary(event_path, _valid_store)
	if int(parsed.get("version", 0)) != STORE_VERSION:
		return
	data["next_sequence"] = max(1, int(parsed.get("next_sequence", 1)))
	var events = parsed.get("events", [])
	if typeof(events) == TYPE_ARRAY:
		for event in events:
			if typeof(event) == TYPE_DICTIONARY and str(event.get("kind", "")).strip_edges() != "":
				data["events"].append(event.duplicate(true))
		data["events"] = _trim_events(data["events"])
	var daily = parsed.get("daily", {})
	if typeof(daily) == TYPE_DICTIONARY:
		for date in daily:
			if _valid_date(str(date)) and typeof(daily[date]) == TYPE_DICTIONARY:
				data["daily"][date] = _sanitize_summary(daily[date])


static func date_for_unix(unix_time: int) -> String:
	var bias = int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_string_from_unix_time(unix_time + bias * 60).substr(0, 10)


static func empty_summary() -> Dictionary:
	return {"counts": {}, "mode_counts": {}, "period_counts": {}, "interaction_counts": {}, "total_events": 0, "user_interactions": 0, "care_score": 0, "play_score": 0, "disruption_score": 0, "last_event_at": 0, "last_event_kind": ""}


func _apply_event(bucket: Dictionary, event: Dictionary) -> void:
	var kind = str(event["kind"])
	bucket["total_events"] += 1
	_increment(bucket["counts"], kind)
	for field in ["mode", "period"]:
		var value = str(event[field]).strip_edges()
		if value != "":
			_increment(bucket[field + "_counts"], value)
	if event["source"] == "user" and kind in USER_INTERACTION_KINDS:
		bucket["user_interactions"] += 1
		_increment(bucket["interaction_counts"], kind)
	if kind in CARE_KINDS:
		bucket["care_score"] += 1
	if kind in PLAY_KINDS:
		bucket["play_score"] += 1
	if kind in DISRUPTIVE_KINDS:
		bucket["disruption_score"] += 1
	if int(event["at"]) >= int(bucket["last_event_at"]):
		bucket["last_event_at"] = event["at"]
		bucket["last_event_kind"] = kind


func _sanitize_summary(value: Dictionary) -> Dictionary:
	var result = empty_summary()
	for field in COUNT_FIELDS:
		if typeof(value.get(field)) == TYPE_DICTIONARY:
			for key in value[field]:
				var count = value[field][key]
				if typeof(count) in [TYPE_INT, TYPE_FLOAT] and count > 0:
					result[field][str(key)] = int(count)
	for field in TOTAL_FIELDS + ["last_event_at"]:
		if typeof(value.get(field)) in [TYPE_INT, TYPE_FLOAT]:
			result[field] = max(0, int(value[field]))
	result["last_event_kind"] = str(value.get("last_event_kind", ""))
	return result


func _valid_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	if not value.replace("-", "").is_valid_int():
		return false
	var unix = int(Time.get_unix_time_from_datetime_string(value + "T00:00:00"))
	return Time.get_datetime_string_from_unix_time(unix).substr(0, 10) == value


func _valid_store(value: Dictionary) -> bool:
	if value.get("version") != STORE_VERSION or typeof(value.get("daily")) != TYPE_DICTIONARY or typeof(value.get("events")) != TYPE_ARRAY:
		return false
	for date in value["daily"]:
		var bucket = value["daily"][date]
		if not _valid_date(str(date)) or typeof(bucket) != TYPE_DICTIONARY:
			return false
		for field in COUNT_FIELDS:
			if typeof(bucket.get(field)) != TYPE_DICTIONARY:
				return false
			for count in bucket[field].values():
				if typeof(count) not in [TYPE_INT, TYPE_FLOAT] or count < 0:
					return false
		for field in TOTAL_FIELDS + ["last_event_at"]:
			if typeof(bucket.get(field)) not in [TYPE_INT, TYPE_FLOAT] or bucket[field] < 0:
				return false
	return true


func _default_data() -> Dictionary:
	return {"version": STORE_VERSION, "next_sequence": 1, "events": [], "daily": {}}


func _trim_events(events: Array) -> Array:
	return events.slice(max(0, events.size() - MAX_EVENTS))


func _dictionary_or_empty(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _clean_string_array(value) -> Array:
	var result := []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			var clean = str(item).strip_edges()
			if clean != "":
				result.append(clean)
	return result


func _increment(target: Dictionary, key: String) -> void:
	target[key] = int(target.get(key, 0)) + 1


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())
