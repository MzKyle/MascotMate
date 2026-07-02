extends Node

const STATE_VERSION := 2
const CONFIG_DIR_NAME := "crayon-shinchan-desktop-pet"
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


func load_state() -> void:
	state = _default_state()
	if not FileAccess.file_exists(state_path):
		state["last_decay_at"] = _now_unix()
		_request_save()
		return
	var file = FileAccess.open(state_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in CORE_FIELDS:
			if parsed.has(key):
				state[key] = clamp(int(parsed[key]), 0, 100)
		state["version"] = STATE_VERSION
		state["last_decay_at"] = int(parsed.get("last_decay_at", _now_unix()))
		if parsed.has("memory") and typeof(parsed["memory"]) == TYPE_DICTIONARY:
			state["memory"] = _merged_memory(parsed["memory"])
		_request_save()


func save_state() -> void:
	flush_save()


func flush_save() -> void:
	if not dirty:
		return
	var dir = state_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var file = FileAccess.open(state_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state, "\t"))
		dirty = false
	if save_timer != null:
		save_timer.stop()


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
	for key in memory.keys():
		if source.has(key):
			if key == "interaction_counts" and typeof(source[key]) == TYPE_DICTIONARY:
				memory[key] = source[key].duplicate(true)
			elif key != "interaction_counts":
				memory[key] = source[key]
	return memory


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
	var override_dir = OS.get_environment("CRAYON_PET_CONFIG_DIR").strip_edges()
	if override_dir != "":
		return override_dir.path_join("state.json")
	var home = OS.get_environment("HOME")
	if home == "":
		return "user://state.json"
	return home.path_join(".config").path_join(CONFIG_DIR_NAME).path_join("state.json")
