extends Node

const BehaviorDefaults = preload("res://scripts/BehaviorDefaults.gd")
const CompanionBehaviorPolicyScript = preload("res://scripts/CompanionBehaviorPolicy.gd")

signal action_requested(action_name)
signal mischief_requested(kind)
signal prompt_requested(kind, message)
signal effect_requested(kind)
signal decision_observed(decision, context)
signal intent_requested(intent, decision)

const VALID_MODES := BehaviorDefaults.VALID_MODES

var mode := "安静"
var rng := RandomNumberGenerator.new()
var timer: Timer
var paused := false
var skin_behavior_profile := {}
var context_provider := Callable()
var local_memory := {
	"last_interaction_at": 0,
	"last_prompt_at": 0,
	"last_action_at": 0,
}
var behavior_policy = CompanionBehaviorPolicyScript.new()
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
	behavior_policy.configure(config)
	behavior_policy.set_skin_behavior_profile(skin_behavior_profile)
	behavior_policy.set_mode(mode)
	if timer != null:
		schedule_next()


func set_context_provider(provider: Callable) -> void:
	context_provider = provider


func set_skin_behavior_profile(profile: Dictionary) -> void:
	skin_behavior_profile = profile.duplicate(true)
	behavior_policy.set_skin_behavior_profile(profile)
	if timer != null:
		schedule_next()


func set_mode(value: String) -> void:
	var previous_mode = mode
	mode = value if value in VALID_MODES else "安静"
	behavior_policy.set_mode(mode)
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
	behavior_policy.set_mode(mode)
	var forced_state := {
		"kind": forced_mischief_kind,
		"ready_at": forced_mischief_ready_at,
		"expires_at": forced_mischief_expires_at,
	}
	var decision = behavior_policy.decide(context, now_unix, local_memory.duplicate(true), forced_state, paused)
	_apply_forced_state(forced_state)
	return decision


func _decide() -> void:
	var context = _current_context()
	var decision = decide(context)
	emit_signal("decision_observed", decision.duplicate(true), context.duplicate(false))
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
	var intent = decision.get("intent", {})
	if typeof(intent) == TYPE_DICTIONARY and not intent.is_empty():
		emit_signal("intent_requested", intent.duplicate(true), decision.duplicate(true))
	if decision_type == "mischief":
		emit_signal("mischief_requested", str(decision.get("name", "")))
	elif decision_type == "effect":
		emit_signal("effect_requested", str(decision.get("name", "")))
	elif decision_type == "prompt":
		emit_signal("prompt_requested", str(decision.get("name", "")), str(decision.get("message", "")))
	else:
		emit_signal("action_requested", str(decision.get("name", "")))


func _apply_forced_state(forced_state: Dictionary) -> void:
	forced_mischief_kind = str(forced_state.get("kind", ""))
	forced_mischief_ready_at = float(forced_state.get("ready_at", 0.0))
	forced_mischief_expires_at = float(forced_state.get("expires_at", 0.0))


func _current_context() -> Dictionary:
	if context_provider.is_valid():
		var value = context_provider.call()
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {"mode": mode, "busy": false, "state": {}}


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
		event_context["period"] = period_for(now)
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


func _intent_key(intent: Dictionary) -> String:
	var intent_type = str(intent.get("type", ""))
	var intent_name = str(intent.get("name", ""))
	if intent_type == "" or intent_name == "":
		return ""
	return "%s:%s" % [intent_type, intent_name]


func period_for(now: int) -> String:
	return behavior_policy.period_for(now)


func _period_for(now: int) -> String:
	return period_for(now)


func _interval_for_mode(target_mode: String) -> Vector2:
	return behavior_policy.interval_for_mode(target_mode)


func _initial_delay_for_mode(target_mode: String) -> float:
	return behavior_policy.initial_delay_for_mode(target_mode)


func _coerce_now(now_unix: int) -> int:
	return now_unix if now_unix > 0 else int(Time.get_unix_time_from_system())


func _coerce_now_float(now_unix: int) -> float:
	return float(now_unix) if now_unix > 0 else Time.get_unix_time_from_system()
