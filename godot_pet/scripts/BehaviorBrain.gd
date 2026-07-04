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
		"adaptation": {
			"enabled": true,
			"strength": "visible",
			"active_cooldown_multiplier_range": [0.55, 1.65],
			"mischief_cooldown_multiplier_range": [0.50, 1.80],
			"weight_multiplier_range": [0.25, 2.75],
		},
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
	var adaptation = _adaptation_for_context(context, status, period)

	var forced_decision = _forced_mischief_decision(float(now), paused or bool(context.get("busy", false)), period, adaptation)
	if not forced_decision.is_empty():
		return forced_decision

	if paused or bool(context.get("busy", false)):
		return {"type": "none", "retry_after": 2.0}

	var urgent = _urgent_decision(status, memory, period, now, adaptation)
	if not urgent.is_empty():
		return urgent

	var remaining = _attention_cooldown_remaining(memory, period, now, adaptation)
	if remaining > 0.0:
		return {"type": "none", "retry_after": clamp(remaining, 10.0, 120.0)}
	if mode == "安静":
		return {"type": "none", "retry_after": float(companion_config.get("tick_seconds", 60.0))}
	if period == "rest":
		return _attach_adaptation(_attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "rest_period", "period is rest and active behavior should sleep", 85, "action:sleep", "low")
		), adaptation)

	var action = _pick_contextual_action(mode, status, period, adaptation)
	if action.is_empty():
		return {"type": "none", "retry_after": float(companion_config.get("tick_seconds", 60.0))}
	action["retry_after"] = _adapted_cooldown_seconds(period, adaptation)
	action["intent"] = _intent_for_contextual_action(action, status, period, adaptation)
	action = _attach_adaptation(action, adaptation)
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


func _urgent_decision(status: Dictionary, memory: Dictionary, period: String, now: int, adaptation: Dictionary) -> Dictionary:
	var hunger = int(status.get("hunger", 60))
	var energy = int(status.get("energy", 80))
	var mood = int(status.get("mood", 70))
	var hunger_threshold = int(adaptation.get("hunger_threshold", 80))
	var play_threshold = int(adaptation.get("play_threshold", 35))
	if energy <= 20:
		return _attach_adaptation(_attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "sleepy", "energy <= 20", 95, "action:sleep", "low")
		), adaptation)
	if period == "rest" and energy < 85:
		return _attach_adaptation(_attach_intent(
			{"type": "action", "name": "sleep", "retry_after": 180.0},
			_intent("rest_request", "rest_period", "period is rest and energy < 85", 90, "action:sleep", "low")
		), adaptation)
	if hunger >= hunger_threshold and period != "rest":
		var last_feed = int(memory.get("last_feed_at", 0))
		if now - last_feed >= 2 * 60 * 60 and _attention_cooldown_remaining(memory, period, now, adaptation) <= 0.0:
			return _attach_adaptation(_attach_intent(
				{"type": "prompt", "name": "hungry", "message": "有点饿了。", "retry_after": _adapted_cooldown_seconds(period, adaptation)},
				_intent("care_request", "hungry", _reason_with_adaptation("hunger >= %d and last_feed_at older than 2h" % hunger_threshold, adaptation), 90, "prompt:hungry", "low")
			), adaptation)
	if mood <= play_threshold and period == "entertainment" and _attention_cooldown_remaining(memory, period, now, adaptation) <= 0.0:
		return _attach_adaptation(_attach_intent(
			{"type": "prompt", "name": "play", "message": "要不要玩一会儿？", "retry_after": _adapted_cooldown_seconds(period, adaptation)},
			_intent("play_request", "low_mood", _reason_with_adaptation("mood <= %d during entertainment period" % play_threshold, adaptation), 80, "prompt:play", "low")
		), adaptation)
	return {}


func _pick_contextual_action(target_mode: String, status: Dictionary, period: String, adaptation: Dictionary) -> Dictionary:
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
		weight *= _weight_multiplier_for(action_type, action_name, adaptation)
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


func _intent_for_contextual_action(action: Dictionary, status: Dictionary, period: String, adaptation: Dictionary) -> Dictionary:
	var action_type = str(action.get("type", ""))
	var action_name = str(action.get("name", ""))
	var reason = _reason_with_adaptation("weighted action selected for %s mode during %s period" % [mode, period], adaptation)
	if action_type == "mischief" and action_name == "grab":
		return _intent("mischief", "grab_mouse", reason, 70, "mischief:grab", "medium", "weighted")
	if action_type == "effect" and action_name == "footprint":
		return _intent("ambient", "footprint", reason, 35, "effect:footprint", "low", "weighted")
	if action_name == "edge":
		return _intent("ambient", "edge_peek", reason, 40, "action:edge", "low", "weighted")
	if action_name == "invite":
		return _intent("play_request", "invite", _reason_with_adaptation("weighted invite selected with mood %d" % int(status.get("mood", 70)), adaptation), 55, "action:invite", "low", "weighted")
	if action_name == "walk":
		return _intent("ambient", "walk", reason, 35, "action:walk", "low", "weighted")
	if action_name == "idle":
		return _intent("ambient", "idle", reason, 25, "action:idle", "low", "weighted")
	if action_name == "companion":
		return _intent("ambient", "companion_pose", reason, 35, "action:companion", "low", "weighted")
	return _intent("ambient", action_name if action_name != "" else action_type, reason, 30, "%s:%s" % [action_type, action_name], "low", "weighted")


func _attention_cooldown_remaining(memory: Dictionary, period: String, now: int, adaptation := {}) -> float:
	var last_attention = max(
		int(memory.get("last_prompt_at", 0)),
		int(memory.get("last_action_at", 0))
	)
	var last_interaction = int(memory.get("last_interaction_at", 0))
	last_attention = max(last_attention, last_interaction)
	if last_attention <= 0:
		return 0.0
	return max(0.0, _adapted_cooldown_seconds(period, adaptation) - float(now - last_attention))


func _forced_mischief_decision(now: float, blocked: bool, period: String, adaptation: Dictionary) -> Dictionary:
	if forced_mischief_kind == "":
		return {}
	if now > forced_mischief_expires_at:
		clear_forced_mischief()
		return {}
	if blocked:
		return {"type": "none", "retry_after": _forced_retry_after(now)}
	if now < forced_mischief_ready_at:
		return {"type": "none", "retry_after": max(0.1, min(1.0, forced_mischief_ready_at - now))}
	return _attach_adaptation({
		"type": "mischief",
		"name": forced_mischief_kind,
		"forced_mischief": true,
		"retry_after": _adapted_cooldown_seconds(period, adaptation),
		"intent": _intent("mischief", "grab_mouse", _reason_with_adaptation("forced mischief requested and ready", adaptation), 90, "mischief:%s" % forced_mischief_kind, "medium", "forced"),
	}, adaptation)


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


func _adapted_cooldown_seconds(period: String, adaptation := {}) -> float:
	var base = _cooldown_seconds(period)
	if typeof(adaptation) != TYPE_DICTIONARY or not bool(adaptation.get("enabled", false)):
		return base
	var multiplier = max(0.01, float(adaptation.get("cooldown_multiplier", 1.0)))
	var adapted = base * multiplier
	if period == "work":
		return max(base, adapted)
	if period == "rest":
		return max(1800.0, adapted)
	if mode == "安静":
		return base
	return max(30.0, adapted)


func _adaptation_for_context(context: Dictionary, _status: Dictionary, period: String) -> Dictionary:
	var config = companion_config.get("adaptation", {})
	if typeof(config) != TYPE_DICTIONARY:
		config = {}
	var enabled = bool(config.get("enabled", true))
	var result := {
		"enabled": enabled,
		"strength": str(config.get("strength", "visible")),
		"cooldown_multiplier": 1.0,
		"hunger_threshold": 80,
		"play_threshold": 35,
		"weight_multipliers": {},
		"reasons": [],
	}
	if not enabled:
		return result

	var personality = context.get("personality", {})
	if typeof(personality) != TYPE_DICTIONARY:
		personality = {}
	var traits = personality.get("traits", {})
	if typeof(traits) != TYPE_DICTIONARY:
		traits = {}
	var playfulness = clampi(int(traits.get("playfulness", 50)), 0, 100)
	var mischief = clampi(int(traits.get("mischief", 50)), 0, 100)
	var patience = clampi(int(traits.get("patience", 50)), 0, 100)
	var clinginess = clampi(int(traits.get("clinginess", 50)), 0, 100)
	var play_norm = _trait_norm(playfulness)
	var mischief_norm = _trait_norm(mischief)
	var patience_norm = _trait_norm(patience)
	var cling_norm = _trait_norm(clinginess)

	var companion_memory = context.get("memory", {})
	if typeof(companion_memory) != TYPE_DICTIONARY:
		companion_memory = {}
	var preferences = companion_memory.get("preferences", {})
	if typeof(preferences) != TYPE_DICTIONARY:
		preferences = {}
	var favorites = _clean_string_array(preferences.get("favorite_interactions", []))
	var relationship = companion_memory.get("relationship", {})
	if typeof(relationship) != TYPE_DICTIONARY:
		relationship = {}
	var familiarity = clampf(float(relationship.get("familiarity", 1.0)) / 100.0, 0.0, 1.0)
	var care_score = clampf(float(relationship.get("care_score", 0.0)) / 100.0, 0.0, 1.0)
	var play_score = clampf(float(relationship.get("play_score", 0.0)) / 100.0, 0.0, 1.0)

	var strength_scale = _adaptation_strength_scale(str(config.get("strength", "visible")))
	var feed_favorite = "feed_success" in favorites
	var play_favorite = "tease_success" in favorites or "tease_start" in favorites
	var poke_favorite = "poke_body" in favorites or "grab_start" in favorites or "throw_fast" in favorites
	var peek_favorite = "peek_enter" in favorites or "peek_exit" in favorites

	var care_bias = (0.65 if feed_favorite else 0.0) + care_score * 0.45 + familiarity * 0.25 + max(0.0, -patience_norm) * 0.2
	result["hunger_threshold"] = clampi(int(round(80.0 - min(1.0, care_bias * strength_scale) * 6.0)), 74, 80)
	var play_bias = max(0.0, play_norm) * 0.45 + (0.65 if play_favorite else 0.0) + play_score * 0.35 + familiarity * 0.25 + max(0.0, cling_norm) * 0.25
	result["play_threshold"] = clampi(int(round(35.0 + min(1.0, play_bias * strength_scale) * 15.0)), 35, 50)

	var active_cooldown_bias = max(0.0, play_norm) * 0.35 + max(0.0, cling_norm) * 0.25 + familiarity * 0.25 + (0.20 if play_favorite else 0.0) - patience_norm * 0.30
	var mischief_cooldown_bias = max(0.0, mischief_norm) * 0.55 + (0.25 if poke_favorite else 0.0) - patience_norm * 0.40
	var cooldown_multiplier = 1.0
	if mode == "捣乱":
		cooldown_multiplier = 1.0 - mischief_cooldown_bias * strength_scale
		cooldown_multiplier = _clamp_to_range(cooldown_multiplier, config.get("mischief_cooldown_multiplier_range", [0.50, 1.80]), 0.50, 1.80)
	elif mode == "活泼":
		cooldown_multiplier = 1.0 - active_cooldown_bias * strength_scale
		cooldown_multiplier = _clamp_to_range(cooldown_multiplier, config.get("active_cooldown_multiplier_range", [0.55, 1.65]), 0.55, 1.65)
	result["cooldown_multiplier"] = cooldown_multiplier

	var multipliers := {}
	multipliers["walk"] = 1.0 + play_norm * 0.65 - patience_norm * 0.15 + familiarity * 0.20
	multipliers["invite"] = 1.0 + play_norm * 0.95 + cling_norm * 0.75 + (0.95 if play_favorite else 0.0) + familiarity * 0.45 - patience_norm * 0.50
	multipliers["idle"] = 1.0 + patience_norm * 0.85 - max(0.0, play_norm) * 0.25
	multipliers["edge"] = 1.0 + mischief_norm * 0.80 + (0.85 if peek_favorite else 0.0) + (0.30 if poke_favorite else 0.0)
	multipliers["footprint"] = 1.0 + play_norm * 0.55 + mischief_norm * 0.55 + (0.45 if poke_favorite else 0.0)
	multipliers["grab"] = 1.0 + mischief_norm * 1.20 + (0.95 if poke_favorite else 0.0) - patience_norm * 0.80
	var range = config.get("weight_multiplier_range", [0.25, 2.75])
	for key in multipliers.keys():
		multipliers[key] = _clamp_to_range(float(multipliers[key]) * strength_scale + (1.0 - strength_scale), range, 0.25, 2.75)
	result["weight_multipliers"] = multipliers

	var reasons := []
	if playfulness >= 70:
		reasons.append("adaptation playfulness boosts active behavior")
	if mischief >= 65:
		reasons.append("adaptation mischief boosts playful trouble")
	if patience >= 70:
		reasons.append("adaptation patience favors idle and longer gaps")
	elif patience <= 35:
		reasons.append("adaptation low patience shortens active gaps")
	if clinginess >= 70:
		reasons.append("adaptation clinginess boosts invite")
	if play_favorite:
		reasons.append("adaptation favorite tease_success boosts play")
	if feed_favorite:
		reasons.append("adaptation favorite feed_success lowers hunger prompt threshold")
	if poke_favorite:
		reasons.append("adaptation playful touch history boosts mischief")
	if peek_favorite:
		reasons.append("adaptation peek history boosts edge behavior")
	if familiarity >= 0.50:
		reasons.append("adaptation familiarity increases responsiveness")
	result["reasons"] = reasons
	return result


func _weight_multiplier_for(action_type: String, action_name: String, adaptation: Dictionary) -> float:
	if typeof(adaptation) != TYPE_DICTIONARY or not bool(adaptation.get("enabled", false)):
		return 1.0
	var multipliers = adaptation.get("weight_multipliers", {})
	if typeof(multipliers) != TYPE_DICTIONARY:
		return 1.0
	var key = action_name
	if action_type == "mischief" and action_name == "grab":
		key = "grab"
	return max(0.0, float(multipliers.get(key, 1.0)))


func _attach_adaptation(decision: Dictionary, adaptation: Dictionary) -> Dictionary:
	var result = decision.duplicate(true)
	if typeof(adaptation) == TYPE_DICTIONARY and bool(adaptation.get("enabled", false)):
		result["adaptation"] = _adaptation_meta(adaptation)
	return result


func _adaptation_meta(adaptation: Dictionary) -> Dictionary:
	var reasons = adaptation.get("reasons", [])
	if typeof(reasons) != TYPE_ARRAY:
		reasons = []
	return {
		"enabled": bool(adaptation.get("enabled", false)),
		"strength": str(adaptation.get("strength", "visible")),
		"cooldown_multiplier": float(adaptation.get("cooldown_multiplier", 1.0)),
		"hunger_threshold": int(adaptation.get("hunger_threshold", 80)),
		"play_threshold": int(adaptation.get("play_threshold", 35)),
		"weight_multipliers": adaptation.get("weight_multipliers", {}).duplicate(true) if typeof(adaptation.get("weight_multipliers", {})) == TYPE_DICTIONARY else {},
		"reasons": reasons.duplicate(true),
	}


func _reason_with_adaptation(base_reason: String, adaptation: Dictionary) -> String:
	if typeof(adaptation) != TYPE_DICTIONARY or not bool(adaptation.get("enabled", false)):
		return base_reason
	var reasons = adaptation.get("reasons", [])
	if typeof(reasons) != TYPE_ARRAY or reasons.is_empty():
		return base_reason
	var limited := []
	for i in range(min(3, reasons.size())):
		limited.append(str(reasons[i]))
	return "%s; %s" % [base_reason, "; ".join(limited)]


func _trait_norm(value: int) -> float:
	return (float(clampi(value, 0, 100)) - 50.0) / 50.0


func _adaptation_strength_scale(value: String) -> float:
	if value == "subtle":
		return 0.55
	if value == "bold":
		return 1.20
	return 1.0


func _clamp_to_range(value: float, range_value, default_min: float, default_max: float) -> float:
	var min_value = default_min
	var max_value = default_max
	if typeof(range_value) == TYPE_ARRAY and range_value.size() >= 2:
		min_value = float(range_value[0])
		max_value = float(range_value[1])
	if max_value < min_value:
		var tmp = min_value
		min_value = max_value
		max_value = tmp
	return clamp(value, min_value, max_value)


func _clean_string_array(value) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		var text = str(item).strip_edges()
		if text != "":
			result.append(text)
	return result


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
	if source.has("adaptation"):
		merged["adaptation"] = _merged_adaptation_config(source["adaptation"], merged.get("adaptation", {}))
	return merged


func _merged_adaptation_config(source, defaults) -> Dictionary:
	var merged = defaults.duplicate(true) if typeof(defaults) == TYPE_DICTIONARY else DEFAULT_BEHAVIOR["companion"]["adaptation"].duplicate(true)
	if typeof(source) != TYPE_DICTIONARY:
		return merged
	if source.has("enabled"):
		merged["enabled"] = bool(source["enabled"])
	if source.has("strength"):
		var strength = str(source["strength"])
		merged["strength"] = strength if strength in ["subtle", "visible", "bold"] else "visible"
	for key in ["active_cooldown_multiplier_range", "mischief_cooldown_multiplier_range", "weight_multiplier_range"]:
		if source.has(key) and typeof(source[key]) == TYPE_ARRAY and source[key].size() >= 2:
			var min_value = max(0.01, float(source[key][0]))
			var max_value = max(min_value, float(source[key][1]))
			merged[key] = [min_value, max_value]
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
