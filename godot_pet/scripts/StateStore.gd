extends Node

const AtomicJson = preload("res://scripts/AtomicJson.gd")
const STATE_VERSION := 2
const SAVE_DEBOUNCE_SECONDS := 5.0
const MIN_DECAY_SECONDS := 1800
const MAX_OFFLINE_DECAY_SECONDS := 8 * 60 * 60
const CORE_FIELDS := ["mood", "hunger", "energy", "affection"]
const DEFAULT_MEMORY := {
	"last_interaction_at": 0,
	"last_interaction_kind": "",
	"last_feed_at": 0,
	"last_play_at": 0,
	"last_prompt_at": 0,
	"last_action_at": 0,
	"interaction_counts": {},
}

var state := {
	"version": STATE_VERSION,
	"mood": 70,
	"hunger": 60,
	"energy": 80,
	"affection": 30,
	"last_decay_at": 0,
	"memory": DEFAULT_MEMORY.duplicate(true),
}
var state_path := ""
var save_timer: Timer
var dirty := false
var _load_error: Error = OK
var _last_save_error: Error = OK


func _ready() -> void:
	state_path = _state_path()
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	save_timer.timeout.connect(flush_save)
	add_child(save_timer)
	load_state()


func _exit_tree() -> void:
	flush_save()


func load_state() -> Error:
	if save_timer != null:
		save_timer.stop()
	dirty = false
	state = _default_state()
	state["last_decay_at"] = _now_unix()
	var loaded := AtomicJson.load_dictionary(state_path, _valid_state)
	var error: Error = loaded["error"]
	var primary_error: Error = loaded["primary_error"]
	_load_error = primary_error if not AtomicJson.can_replace(primary_error) else OK
	if not AtomicJson.can_replace(error):
		_load_error = error
	if error == OK:
		var parsed: Dictionary = loaded["data"]
		state.merge(parsed, true)
		for key in CORE_FIELDS:
			state[key] = clampi(int(state[key]), 0, 100)
		state["version"] = maxi(STATE_VERSION, int(parsed.get("version", 1)))
		state["last_decay_at"] = int(state["last_decay_at"])
		state["memory"] = _merged_memory(state["memory"])
	if _load_error == OK and (error == ERR_FILE_NOT_FOUND or (error == OK and primary_error != OK)):
		_request_save()
	return error if _load_error == OK else _load_error


func save_state() -> Error:
	return flush_save()


func flush_save() -> Error:
	if not dirty:
		return OK
	if save_timer != null:
		save_timer.stop()
	var error := _load_error
	if error == OK:
		error = AtomicJson.write_dictionary(state_path, state, _valid_state, true)
	if error == OK:
		dirty = false
	else:
		if error != _last_save_error:
			push_warning("Could not save %s: %s" % [state_path, error_string(error)])
		if _load_error == OK and save_timer != null and save_timer.is_inside_tree():
			save_timer.start(SAVE_DEBOUNCE_SECONDS)
	_last_save_error = error
	return error


func snapshot() -> Dictionary:
	return state.duplicate(true)


func apply(deltas: Dictionary) -> Dictionary:
	var changes := {}
	for key in deltas.keys():
		if not key in CORE_FIELDS:
			continue
		var before = int(state.get(key, 0))
		var after = clamp(before + int(deltas[key]), 0, 100)
		state[key] = after
		changes[key] = after - before
	if not changes.is_empty():
		_request_save()
	return changes


func feed() -> Dictionary:
	return apply({"hunger": -25, "mood": 5, "affection": 3})


func pet() -> Dictionary:
	return apply({"mood": 4, "affection": 6})


func poke() -> Dictionary:
	return apply({"mood": -1, "affection": 1})


func play() -> Dictionary:
	return apply({"mood": 12, "affection": 6, "energy": -8, "hunger": 4})


func sleep_tick() -> Dictionary:
	return apply({"energy": 6, "mood": 1})


func record_interaction(kind: String, now_unix := 0) -> void:
	var now = _coerce_now(now_unix)
	var memory: Dictionary = state.get("memory", DEFAULT_MEMORY.duplicate(true))
	memory["last_interaction_at"] = now
	memory["last_interaction_kind"] = kind
	if kind == "feed":
		memory["last_feed_at"] = now
	elif kind == "play":
		memory["last_play_at"] = now
	var counts: Dictionary = memory.get("interaction_counts", {})
	counts[kind] = int(counts.get(kind, 0)) + 1
	memory["interaction_counts"] = counts
	state["memory"] = memory
	_request_save()


func record_action(kind: String, now_unix := 0) -> void:
	var memory: Dictionary = state.get("memory", DEFAULT_MEMORY.duplicate(true))
	memory["last_action_at"] = _coerce_now(now_unix)
	state["memory"] = memory
	_request_save()


func record_prompt(kind: String, now_unix := 0) -> void:
	var memory: Dictionary = state.get("memory", DEFAULT_MEMORY.duplicate(true))
	memory["last_prompt_at"] = _coerce_now(now_unix)
	memory["last_prompt_kind"] = kind
	state["memory"] = memory
	_request_save()


func apply_passive_time(now_unix: int, period: String) -> Dictionary:
	var now = _coerce_now(now_unix)
	var last = int(state.get("last_decay_at", 0))
	if last <= 0:
		state["last_decay_at"] = now
		_request_save()
		return {}
	if now <= last:
		return {}
	var elapsed = now - last
	if elapsed < MIN_DECAY_SECONDS:
		return {}
	var capped_elapsed = min(elapsed, MAX_OFFLINE_DECAY_SECONDS)
	var hours = float(capped_elapsed) / 3600.0
	var deltas := {}
	if period == "rest":
		_set_nonzero_delta(deltas, "energy", int(round(8.0 * hours)))
		_set_nonzero_delta(deltas, "hunger", int(round(2.0 * hours)))
	else:
		_set_nonzero_delta(deltas, "hunger", int(round(4.0 * hours)))
		_set_nonzero_delta(deltas, "energy", -int(round(3.0 * hours)))
	if hours >= 1.0 and (int(state.get("hunger", 0)) > 75 or int(state.get("energy", 0)) < 25):
		_set_nonzero_delta(deltas, "mood", -max(1, int(round(hours))))
	state["last_decay_at"] = now
	var changes = apply(deltas)
	if changes.is_empty():
		_request_save()
	return changes


func _default_state() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"mood": 70,
		"hunger": 60,
		"energy": 80,
		"affection": 30,
		"last_decay_at": 0,
		"memory": DEFAULT_MEMORY.duplicate(true),
	}


func _merged_memory(source: Dictionary) -> Dictionary:
	var memory = DEFAULT_MEMORY.duplicate(true)
	memory.merge(source, true)
	return memory


func _valid_state(value: Dictionary) -> bool:
	var version = value.get("version", 1)
	if not AtomicJson.is_number(version, true) or float(version) < 0.0:
		return false
	for key in CORE_FIELDS + ["last_decay_at"]:
		if value.has(key) and not AtomicJson.is_number(value[key]):
			return false
	var memory = value.get("memory", {})
	if typeof(memory) != TYPE_DICTIONARY:
		return false
	for key in ["last_interaction_at", "last_feed_at", "last_play_at", "last_prompt_at", "last_action_at"]:
		if memory.has(key) and not AtomicJson.is_number(memory[key]):
			return false
	var counts = memory.get("interaction_counts", {})
	if typeof(counts) != TYPE_DICTIONARY:
		return false
	for count in counts.values():
		if not AtomicJson.is_number(count):
			return false
	return true


func _set_nonzero_delta(deltas: Dictionary, key: String, value: int) -> void:
	if value != 0:
		deltas[key] = value


func _request_save() -> void:
	dirty = true
	if save_timer != null and save_timer.is_inside_tree():
		save_timer.start(SAVE_DEBOUNCE_SECONDS)


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else _now_unix()


func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())


func _state_path() -> String:
	return preload("res://scripts/AppPaths.gd").data_dir().path_join("state.json")
