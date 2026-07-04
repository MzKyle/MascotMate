extends Node

const STORE_VERSION := 1
const MAX_EVENTS := 200
const FILE_NAME := "companion_events.json"

var event_path := ""
var data := _default_data()


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
	var events = data.get("events", [])
	if typeof(events) != TYPE_ARRAY:
		events = []
	events.append(event)
	data["events"] = _trim_events(events)
	data["next_sequence"] = sequence + 1
	flush_save()
	return event


func recent_events(limit := 20) -> Array:
	var events = data.get("events", [])
	if typeof(events) != TYPE_ARRAY:
		return []
	var clean_limit = clampi(int(limit), 0, MAX_EVENTS)
	if clean_limit <= 0:
		return []
	var start = max(0, events.size() - clean_limit)
	var result := []
	for i in range(start, events.size()):
		if typeof(events[i]) == TYPE_DICTIONARY:
			result.append(events[i].duplicate(true))
	return result


func flush_save() -> void:
	if event_path == "":
		return
	DirAccess.make_dir_recursive_absolute(event_path.get_base_dir())
	var file = FileAccess.open(event_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))


func _load_events() -> void:
	data = _default_data()
	if event_path == "" or not FileAccess.file_exists(event_path):
		return
	var file = FileAccess.open(event_path, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	data["version"] = STORE_VERSION
	data["next_sequence"] = max(1, int(parsed.get("next_sequence", 1)))
	var events = parsed.get("events", [])
	if typeof(events) == TYPE_ARRAY:
		var clean_events := []
		for event in events:
			if typeof(event) == TYPE_DICTIONARY and str(event.get("kind", "")).strip_edges() != "":
				clean_events.append(event.duplicate(true))
		data["events"] = _trim_events(clean_events)


func _default_data() -> Dictionary:
	return {
		"version": STORE_VERSION,
		"next_sequence": 1,
		"events": [],
	}


func _trim_events(events: Array) -> Array:
	if events.size() <= MAX_EVENTS:
		return events
	return events.slice(events.size() - MAX_EVENTS, events.size())


func _dictionary_or_empty(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return {}


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
