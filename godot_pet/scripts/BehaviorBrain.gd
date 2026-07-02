extends Node

signal action_requested(action_name)
signal mischief_requested(kind)

const DEFAULT_BEHAVIOR := {
	"modes": {
		"安静": {
			"interval": [4.0, 8.0],
			"actions": [],
		},
		"活泼": {
			"interval": [4.0, 8.0],
			"actions": [
				{"type": "action", "name": "walk", "weight": 34.0},
				{"type": "action", "name": "idle", "weight": 18.0},
				{"type": "action", "name": "edge", "weight": 14.0},
				{"type": "action", "name": "invite", "weight": 14.0},
				{"type": "mischief", "name": "footprint", "weight": 20.0},
			],
		},
		"捣乱": {
			"interval": [20.0, 40.0],
			"initial_delay": 1.0,
			"actions": [
				{"type": "mischief", "name": "grab", "weight": 1.0},
			],
		},
	},
}

var mode := "安静"
var rng := RandomNumberGenerator.new()
var timer: Timer
var paused := false
var behavior_config := DEFAULT_BEHAVIOR.duplicate(true)


func _ready() -> void:
	rng.randomize()
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_decide)
	add_child(timer)
	schedule_next()


func configure(config: Dictionary) -> void:
	behavior_config = _merged_behavior_config(config)
	if timer != null:
		schedule_next()


func set_mode(value: String) -> void:
	var previous_mode = mode
	if value in ["安静", "活泼", "捣乱"]:
		mode = value
	else:
		mode = "安静"
	if timer != null:
		var initial_delay = _initial_delay_for_mode(mode)
		if initial_delay > 0.0 and previous_mode != mode:
			schedule_soon(initial_delay)
		else:
			schedule_next()


func set_paused(value: bool) -> void:
	paused = value


func schedule_next() -> void:
	var interval = _interval_for_mode(mode)
	timer.start(rng.randf_range(interval.x, interval.y))


func schedule_soon(seconds := 1.0) -> void:
	if timer != null:
		timer.start(max(0.1, seconds))


func _decide() -> void:
	if paused:
		schedule_next()
		return
	var action = _pick_action_for_mode(mode)
	if action.is_empty():
		schedule_next()
		return
	if str(action.get("type", "")) == "mischief":
		emit_signal("mischief_requested", str(action.get("name", "")))
	else:
		emit_signal("action_requested", str(action.get("name", "")))
	schedule_next()


func _interval_for_mode(target_mode: String) -> Vector2:
	var mode_config = _mode_config(target_mode)
	var interval = mode_config.get("interval", [4.0, 8.0])
	if typeof(interval) != TYPE_ARRAY or interval.size() < 2:
		return Vector2(4.0, 8.0)
	var min_value = max(0.1, float(interval[0]))
	var max_value = max(min_value, float(interval[1]))
	return Vector2(min_value, max_value)


func _initial_delay_for_mode(target_mode: String) -> float:
	return max(0.0, float(_mode_config(target_mode).get("initial_delay", 0.0)))


func _pick_action_for_mode(target_mode: String) -> Dictionary:
	var actions = _mode_config(target_mode).get("actions", [])
	if typeof(actions) != TYPE_ARRAY or actions.is_empty():
		return {}
	var total := 0.0
	for action in actions:
		if typeof(action) == TYPE_DICTIONARY:
			total += max(0.0, float(action.get("weight", 0.0)))
	if total <= 0.0:
		return {}
	var roll = rng.randf_range(0.0, total)
	var cursor := 0.0
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			continue
		cursor += max(0.0, float(action.get("weight", 0.0)))
		if roll <= cursor:
			return action
	return actions[actions.size() - 1] if typeof(actions[actions.size() - 1]) == TYPE_DICTIONARY else {}


func _mode_config(target_mode: String) -> Dictionary:
	var modes = behavior_config.get("modes", {})
	if typeof(modes) == TYPE_DICTIONARY and modes.has(target_mode) and typeof(modes[target_mode]) == TYPE_DICTIONARY:
		return modes[target_mode]
	return DEFAULT_BEHAVIOR["modes"].get(target_mode, DEFAULT_BEHAVIOR["modes"]["安静"])


func _merged_behavior_config(source: Dictionary) -> Dictionary:
	var merged = DEFAULT_BEHAVIOR.duplicate(true)
	if not source.has("modes") or typeof(source["modes"]) != TYPE_DICTIONARY:
		return merged
	for mode_name in merged["modes"].keys():
		if not source["modes"].has(mode_name) or typeof(source["modes"][mode_name]) != TYPE_DICTIONARY:
			continue
		var incoming: Dictionary = source["modes"][mode_name]
		if incoming.has("interval"):
			var interval = incoming["interval"]
			if typeof(interval) == TYPE_ARRAY and interval.size() >= 2:
				merged["modes"][mode_name]["interval"] = [max(0.1, float(interval[0])), max(0.1, float(interval[1]))]
		if incoming.has("initial_delay"):
			merged["modes"][mode_name]["initial_delay"] = max(0.0, float(incoming["initial_delay"]))
		if incoming.has("actions") and typeof(incoming["actions"]) == TYPE_ARRAY:
			var actions := []
			for action in incoming["actions"]:
				if typeof(action) != TYPE_DICTIONARY:
					continue
				var action_type = str(action.get("type", ""))
				var action_name = str(action.get("name", ""))
				var weight = max(0.0, float(action.get("weight", 0.0)))
				if action_type in ["action", "mischief"] and action_name != "" and weight > 0.0:
					actions.append({"type": action_type, "name": action_name, "weight": weight})
			merged["modes"][mode_name]["actions"] = actions
	return merged
