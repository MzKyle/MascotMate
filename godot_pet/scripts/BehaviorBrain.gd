extends Node

signal action_requested(action_name)
signal mischief_requested(kind)
signal prompt_requested(kind, message)
signal effect_requested(kind)

const VALID_MODES := ["安静", "活泼", "捣乱"]
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
				{"type": "effect", "name": "footprint", "weight": 20.0},
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
	"companion": {
		"tick_seconds": 60.0,
		"cooldowns": {
			"安静": 600.0,
			"活泼": 120.0,
			"捣乱": 300.0,
		},
		"work_cooldown_multiplier": 3.0,
	},
}

var mode := "安静"
var rng := RandomNumberGenerator.new()
var timer: Timer
var paused := false
var base_behavior_config := DEFAULT_BEHAVIOR.duplicate(true)
var skin_behavior_profile := {}
var behavior_config := DEFAULT_BEHAVIOR.duplicate(true)
var companion_config := DEFAULT_BEHAVIOR["companion"].duplicate(true)
var context_provider := Callable()
var local_memory := {
	"last_interaction_at": 0,
	"last_prompt_at": 0,
	"last_action_at": 0,
}
var forced_mischief_kind := ""
var forced_mischief_ready_at := 0.0
var forced_mischief_expires_at := 0.0


func _ready() -> void:
	rng.randomize()
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_decide)
	add_child(timer)
	schedule_next()


func configure(config: Dictionary) -> void:
	base_behavior_config = _merged_behavior_config(config)
	companion_config = _merged_companion_config(config.get("companion", {}))
	_rebuild_behavior_config()
	if timer != null:
		schedule_next()


func set_context_provider(provider: Callable) -> void:
	context_provider = provider


func set_skin_behavior_profile(profile: Dictionary) -> void:
	skin_behavior_profile = profile.duplicate(true)
	_rebuild_behavior_config()
	if timer != null:
		schedule_next()


func set_mode(value: String) -> void:
	var previous_mode = mode
	mode = value if value in VALID_MODES else "安静"
	if mode != "捣乱":
		clear_forced_mischief()
	if timer != null:
		var initial_delay = _initial_delay_for_mode(mode)
		if initial_delay > 0.0 and previous_mode != mode:
			schedule_soon(initial_delay)
		else:
			schedule_next()


func set_paused(value: bool) -> void:
	paused = value


func record_interaction(_kind: String, now_unix := 0) -> void:
	local_memory["last_interaction_at"] = _coerce_now(now_unix)


func request_forced_mischief(kind: String, delay_seconds := 0.8, ttl_seconds := 6.0, now_unix := 0) -> void:
	var clean_kind = kind.strip_edges()
	if clean_kind == "":
		clear_forced_mischief()
		return
	var now = _coerce_now_float(now_unix)
	forced_mischief_kind = clean_kind
	forced_mischief_ready_at = now + max(0.0, delay_seconds)
	forced_mischief_expires_at = forced_mischief_ready_at + max(0.1, ttl_seconds)
	schedule_soon(delay_seconds)


func clear_forced_mischief() -> void:
	forced_mischief_kind = ""
	forced_mischief_ready_at = 0.0
	forced_mischief_expires_at = 0.0


func schedule_next() -> void:
	if timer == null:
		return
	var interval = _interval_for_mode(mode)
	timer.start(rng.randf_range(interval.x, interval.y))


func schedule_soon(seconds := 1.0) -> void:
	if timer != null:
		timer.start(max(0.1, seconds))


func decide(context: Dictionary, now_unix := 0) -> Dictionary:
	var now = _coerce_now(now_unix)
	var period = _period_for(now)
	context = context.duplicate(true)
	context["period"] = period
	_apply_passive_time(context, now, period)
	var status = _state_from_context(context)
	var memory = _memory_from_state(status)
	var local_last_interaction = int(local_memory.get("last_interaction_at", 0))
	if local_last_interaction > int(memory.get("last_interaction_at", 0)):
		memory["last_interaction_at"] = local_last_interaction

	var forced_decision = _forced_mischief_decision(float(now), paused or bool(context.get("busy", false)), period)
	if not forced_decision.is_empty():
		return forced_decision

	if paused or bool(context.get("busy", false)):
		return {"type": "none", "retry_after": 2.0}

	var urgent = _urgent_decision(status, memory, period, now)
	if not urgent.is_empty():
		return urgent

	var remaining = _attention_cooldown_remaining(memory, period, now)
	if remaining > 0.0:
		return {"type": "none", "retry_after": clamp(remaining, 10.0, 120.0)}
	if mode == "安静":
		return {"type": "none", "retry_after": float(companion_config.get("tick_seconds", 60.0))}
	if period == "rest":
		return _attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "rest_period", "period is rest and active behavior should sleep", 85, "action:sleep", "low")
		)

	var action = _pick_contextual_action(mode, status, period)
	if action.is_empty():
		return {"type": "none", "retry_after": float(companion_config.get("tick_seconds", 60.0))}
	action["retry_after"] = _cooldown_seconds(period)
	action["intent"] = _intent_for_contextual_action(action, status, period)
	return action


func _decide() -> void:
	var context = _current_context()
	var decision = decide(context)
	_emit_decision(decision, context)
	var retry_after = float(decision.get("retry_after", 0.0))
	if retry_after > 0.0:
		schedule_soon(retry_after)
	else:
		schedule_next()


func _emit_decision(decision: Dictionary, context: Dictionary) -> void:
	var decision_type = str(decision.get("type", "none"))
	if decision_type == "none":
		return
	if bool(decision.get("forced_mischief", false)):
		clear_forced_mischief()
	_remember_decision(decision, context)
	if decision_type == "mischief":
		emit_signal("mischief_requested", str(decision.get("name", "")))
	elif decision_type == "effect":
		emit_signal("effect_requested", str(decision.get("name", "")))
	elif decision_type == "prompt":
		emit_signal("prompt_requested", str(decision.get("name", "")), str(decision.get("message", "")))
	else:
		emit_signal("action_requested", str(decision.get("name", "")))


func _current_context() -> Dictionary:
	if context_provider.is_valid():
		var value = context_provider.call()
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {"mode": mode, "busy": false, "state": {}}


func _apply_passive_time(context: Dictionary, now: int, period: String) -> void:
	var store = context.get("state_store", null)
	if store != null and store.has_method("apply_passive_time"):
		store.apply_passive_time(now, period)
		if store.has_method("snapshot"):
			context["state"] = store.snapshot()


func _urgent_decision(status: Dictionary, memory: Dictionary, period: String, now: int) -> Dictionary:
	var hunger = int(status.get("hunger", 60))
	var energy = int(status.get("energy", 80))
	var mood = int(status.get("mood", 70))
	if energy <= 20:
		return _attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "sleepy", "energy <= 20", 95, "action:sleep", "low")
		)
	if period == "rest" and energy < 85:
		return _attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "rest_period", "period is rest and energy < 85", 90, "action:sleep", "low")
		)
	if hunger >= 80 and period != "rest":
		var last_feed = int(memory.get("last_feed_at", 0))
		if now - last_feed >= 2 * 60 * 60 and _attention_cooldown_remaining(memory, period, now) <= 0.0:
			return _attach_intent(
				{"type": "prompt", "name": "hungry", "message": "有点饿了。", "retry_after": _cooldown_seconds(period)},
				_intent("care_request", "hungry", "hunger >= 80 and last_feed_at older than 2h", 90, "prompt:hungry", "low")
			)
	if mood <= 35 and period == "entertainment" and _attention_cooldown_remaining(memory, period, now) <= 0.0:
		return _attach_intent(
			{"type": "prompt", "name": "play", "message": "要不要玩一会儿？", "retry_after": _cooldown_seconds(period)},
			_intent("play_request", "low_mood", "mood <= 35 during entertainment period", 80, "prompt:play", "low")
		)
	return {}


func _pick_contextual_action(target_mode: String, status: Dictionary, period: String) -> Dictionary:
	var actions = _mode_config(target_mode).get("actions", [])
	if typeof(actions) != TYPE_ARRAY or actions.is_empty():
		return {}
	var weighted := []
	var hunger = int(status.get("hunger", 60))
	var energy = int(status.get("energy", 80))
	var mood = int(status.get("mood", 70))
	for action in actions:
		if typeof(action) != TYPE_DICTIONARY:
			continue
		var action_type = str(action.get("type", ""))
		var action_name = str(action.get("name", ""))
		var weight = max(0.0, float(action.get("weight", 0.0)))
		if action_type == "" or action_name == "" or weight <= 0.0:
			continue
		if period == "rest" and action_type in ["mischief", "effect"]:
			continue
		if period == "work" and action_type in ["mischief", "effect"]:
			weight *= 0.15
		if action_name in ["walk", "edge"]:
			if energy < 30:
				weight *= 0.15
			if hunger > 80:
				weight *= 0.3
			if period == "work":
				weight *= 0.45
		elif action_name == "invite":
			weight *= 1.5 if mood < 50 and period == "entertainment" else 0.3
		elif action_name == "idle":
			if energy < 40:
				weight *= 2.0
		if weight > 0.0:
			weighted.append({"type": action_type, "name": action_name, "weight": weight})
	return _pick_weighted(weighted)


func _pick_weighted(actions: Array) -> Dictionary:
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
			return {"type": str(action.get("type", "")), "name": str(action.get("name", ""))}
	var last = actions[actions.size() - 1]
	return {"type": str(last.get("type", "")), "name": str(last.get("name", ""))} if typeof(last) == TYPE_DICTIONARY else {}


func _intent_for_contextual_action(action: Dictionary, status: Dictionary, period: String) -> Dictionary:
	var action_type = str(action.get("type", ""))
	var action_name = str(action.get("name", ""))
	var reason = "weighted action selected for %s mode during %s period" % [mode, period]
	if action_type == "mischief" and action_name == "grab":
		return _intent("mischief", "grab_mouse", reason, 70, "mischief:grab", "medium", "weighted")
	if action_type == "effect" and action_name == "footprint":
		return _intent("ambient", "footprint", reason, 35, "effect:footprint", "low", "weighted")
	if action_name == "edge":
		return _intent("ambient", "edge_peek", reason, 40, "action:edge", "low", "weighted")
	if action_name == "invite":
		return _intent("play_request", "invite", "weighted invite selected with mood %d" % int(status.get("mood", 70)), 55, "action:invite", "low", "weighted")
	if action_name == "walk":
		return _intent("ambient", "walk", reason, 35, "action:walk", "low", "weighted")
	if action_name == "idle":
		return _intent("ambient", "idle", reason, 25, "action:idle", "low", "weighted")
	if action_name == "companion":
		return _intent("ambient", "companion_pose", reason, 35, "action:companion", "low", "weighted")
	return _intent("ambient", action_name if action_name != "" else action_type, reason, 30, "%s:%s" % [action_type, action_name], "low", "weighted")


func _attention_cooldown_remaining(memory: Dictionary, period: String, now: int) -> float:
	var last_attention = max(
		int(memory.get("last_prompt_at", 0)),
		int(memory.get("last_action_at", 0))
	)
	var last_interaction = int(memory.get("last_interaction_at", 0))
	last_attention = max(last_attention, last_interaction)
	if last_attention <= 0:
		return 0.0
	return max(0.0, _cooldown_seconds(period) - float(now - last_attention))


func _forced_mischief_decision(now: float, blocked: bool, period: String) -> Dictionary:
	if forced_mischief_kind == "":
		return {}
	if now > forced_mischief_expires_at:
		clear_forced_mischief()
		return {}
	if blocked:
		return {"type": "none", "retry_after": _forced_retry_after(now)}
	if now < forced_mischief_ready_at:
		return {"type": "none", "retry_after": max(0.1, min(1.0, forced_mischief_ready_at - now))}
	return {
		"type": "mischief",
		"name": forced_mischief_kind,
		"forced_mischief": true,
		"retry_after": _cooldown_seconds(period),
		"intent": _intent("mischief", "grab_mouse", "forced mischief requested and ready", 90, "mischief:%s" % forced_mischief_kind, "medium", "forced"),
	}


func _forced_retry_after(now: float) -> float:
	if forced_mischief_expires_at <= now:
		return 0.1
	return max(0.1, min(1.0, forced_mischief_expires_at - now))


func _cooldown_seconds(period: String) -> float:
	var cooldowns = companion_config.get("cooldowns", {})
	var seconds = 600.0
	if typeof(cooldowns) == TYPE_DICTIONARY:
		seconds = float(cooldowns.get(mode, seconds))
	if period == "work":
		seconds *= float(companion_config.get("work_cooldown_multiplier", 3.0))
	elif period == "rest":
		seconds = max(seconds, 1800.0)
	return seconds


func _remember_decision(decision: Dictionary, context: Dictionary) -> void:
	var now = _coerce_now(0)
	var decision_type = str(decision.get("type", ""))
	if decision_type == "prompt":
		local_memory["last_prompt_at"] = now
	elif decision_type in ["action", "mischief", "effect"]:
		local_memory["last_action_at"] = now
	var store = context.get("state_store", null)
	if store != null:
		if decision_type == "prompt" and store.has_method("record_prompt"):
			store.record_prompt(str(decision.get("name", "")), now)
		elif decision_type in ["action", "mischief", "effect"] and store.has_method("record_action"):
			store.record_action("%s:%s" % [decision_type, str(decision.get("name", ""))], now)
	_record_automatic_event(decision, context, now)


func _record_automatic_event(decision: Dictionary, context: Dictionary, now: int) -> void:
	var decision_type = str(decision.get("type", ""))
	if not decision_type in ["prompt", "action", "mischief", "effect"]:
		return
	var event_store = context.get("event_store", null)
	if event_store == null or not event_store.has_method("record_event"):
		return
	var event_kind = "auto_action"
	if decision_type == "prompt":
		event_kind = "auto_prompt"
	elif decision_type == "effect":
		event_kind = "auto_effect"
	var intent = decision.get("intent", {})
	if typeof(intent) != TYPE_DICTIONARY:
		intent = {}
	var event_context = context.duplicate(true)
	if not event_context.has("period"):
		event_context["period"] = _period_for(now)
	var store = context.get("state_store", null)
	if store != null and store.has_method("snapshot"):
		event_context["state"] = store.snapshot()
	var meta = {
		"decision_type": decision_type,
		"decision_name": str(decision.get("name", "")),
		"intent_key": _intent_key(intent),
		"reason": str(intent.get("reason", "")),
	}
	var event = event_store.record_event(event_kind, "system", event_context, meta, [decision_type], {}, {}, now)
	var memory_store = context.get("memory_store", null)
	if typeof(event) == TYPE_DICTIONARY and not event.is_empty() and memory_store != null and memory_store.has_method("refresh"):
		memory_store.refresh(now)


func _state_from_context(context: Dictionary) -> Dictionary:
	var status = context.get("state", {})
	if typeof(status) == TYPE_DICTIONARY:
		return status
	return {}


func _memory_from_state(status: Dictionary) -> Dictionary:
	var memory = status.get("memory", {})
	if typeof(memory) != TYPE_DICTIONARY:
		memory = {}
	for key in local_memory.keys():
		if not memory.has(key):
			memory[key] = local_memory[key]
	return memory


func _attach_intent(decision: Dictionary, intent: Dictionary) -> Dictionary:
	var result = decision.duplicate(true)
	result["intent"] = intent
	return result


func _intent(intent_type: String, intent_name: String, reason: String, priority: int, cooldown_key: String, interruption_level: String, source := "rule") -> Dictionary:
	return {
		"type": intent_type,
		"name": intent_name,
		"reason": reason,
		"priority": priority,
		"cooldown_key": cooldown_key,
		"interruption_level": interruption_level,
		"source": source,
	}


func _intent_key(intent: Dictionary) -> String:
	var intent_type = str(intent.get("type", ""))
	var intent_name = str(intent.get("name", ""))
	if intent_type == "" or intent_name == "":
		return ""
	return "%s:%s" % [intent_type, intent_name]


func _period_for(now: int) -> String:
	var time = Time.get_datetime_dict_from_unix_time(now)
	var hour = int(time.get("hour", 12))
	var weekday = int(time.get("weekday", 1))
	var workday = weekday >= 1 and weekday <= 5
	if hour >= 23 or hour < 7:
		return "rest"
	if workday and hour >= 9 and hour < 18:
		return "work"
	return "entertainment"


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


func _mode_config(target_mode: String) -> Dictionary:
	var modes = behavior_config.get("modes", {})
	if typeof(modes) == TYPE_DICTIONARY and modes.has(target_mode) and typeof(modes[target_mode]) == TYPE_DICTIONARY:
		return modes[target_mode]
	return DEFAULT_BEHAVIOR["modes"].get(target_mode, DEFAULT_BEHAVIOR["modes"]["安静"])


func _merged_behavior_config(source: Dictionary) -> Dictionary:
	var merged = DEFAULT_BEHAVIOR.duplicate(true)
	if source.has("modes") and typeof(source["modes"]) == TYPE_DICTIONARY:
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
					if _is_behavior_action_type(action_type) and action_name != "" and weight > 0.0:
						actions.append({"type": action_type, "name": action_name, "weight": weight})
				merged["modes"][mode_name]["actions"] = actions
	return merged


func _merged_companion_config(source) -> Dictionary:
	var merged = DEFAULT_BEHAVIOR["companion"].duplicate(true)
	if typeof(source) != TYPE_DICTIONARY:
		return merged
	if source.has("tick_seconds"):
		merged["tick_seconds"] = max(10.0, float(source["tick_seconds"]))
	if source.has("work_cooldown_multiplier"):
		merged["work_cooldown_multiplier"] = max(1.0, float(source["work_cooldown_multiplier"]))
	if source.has("cooldowns") and typeof(source["cooldowns"]) == TYPE_DICTIONARY:
		var cooldowns: Dictionary = merged["cooldowns"]
		for mode_name in VALID_MODES:
			if source["cooldowns"].has(mode_name):
				cooldowns[mode_name] = max(30.0, float(source["cooldowns"][mode_name]))
		merged["cooldowns"] = cooldowns
	return merged


func _rebuild_behavior_config() -> void:
	behavior_config = base_behavior_config.duplicate(true)
	if typeof(skin_behavior_profile) == TYPE_DICTIONARY and not skin_behavior_profile.is_empty():
		behavior_config = _merge_skin_behavior_profile(behavior_config, skin_behavior_profile)


func _merge_skin_behavior_profile(base: Dictionary, profile: Dictionary) -> Dictionary:
	var merged = base.duplicate(true)
	var modes = profile.get("modes", {})
	if typeof(modes) != TYPE_DICTIONARY:
		return merged
	for mode_name in merged["modes"].keys():
		if not modes.has(mode_name) or typeof(modes[mode_name]) != TYPE_DICTIONARY:
			continue
		var incoming: Dictionary = modes[mode_name]
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
				if _is_behavior_action_type(action_type) and action_name != "" and weight > 0.0:
					actions.append({"type": action_type, "name": action_name, "weight": weight})
			if not actions.is_empty():
				merged["modes"][mode_name]["actions"] = actions
	return merged


func _is_behavior_action_type(value: String) -> bool:
	return value in ["action", "mischief", "effect"]


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())


func _coerce_now_float(now_unix: int) -> float:
	return float(now_unix) if now_unix > 0 else Time.get_unix_time_from_system()
