extends RefCounted

const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")

const AVAILABLE_SCENARIOS := [
	"work_focus",
	"hungry_care",
	"low_mood_play",
	"rest_boundary",
	"busy_guard",
	"mischief_forced",
	"profile_low_interrupt",
	"profile_playful",
	"profile_care",
	"profile_work_protected",
	"profile_rest_protected",
]

var behavior_config := {}
var skin_behavior_profile := {}
var default_personality := {}
var event_store = null


func configure(config: Dictionary, skin_profile := {}, personality := {}, companion_event_store = null) -> void:
	behavior_config = config.duplicate(true)
	skin_behavior_profile = skin_profile.duplicate(true) if typeof(skin_profile) == TYPE_DICTIONARY else {}
	default_personality = personality.duplicate(true) if typeof(personality) == TYPE_DICTIONARY else {}
	event_store = companion_event_store


func run(requested_id := "all") -> Dictionary:
	var selected := []
	for scenario_id in AVAILABLE_SCENARIOS:
		if requested_id == "all" or requested_id == scenario_id:
			selected.append(scenario_id)
	if selected.is_empty():
		selected = AVAILABLE_SCENARIOS.duplicate()
	var events_before = _event_count()
	var result := {
		"version": 1,
		"generated_at": int(Time.get_unix_time_from_system()),
		"requested": requested_id,
		"events_before": events_before,
		"scenarios": [],
	}
	for scenario_id in selected:
		result["scenarios"].append(_run_scenario(scenario_id))
	result["events_after"] = _event_count()
	result["mutated_events"] = int(result["events_after"]) != events_before
	return result


func _run_scenario(scenario_id: String) -> Dictionary:
	var work_time = _debug_unix_for_local_datetime(2025, 11, 3, 11)
	var entertainment_time = _debug_unix_for_local_datetime(2025, 11, 1, 20)
	var rest_time = _debug_unix_for_local_datetime(2025, 11, 3, 2)
	var now = entertainment_time
	var mode = "活泼"
	var context := {
		"busy": false,
		"state": _debug_calm_state(now),
		"memory": _debug_adaptive_memory([], 40, 20, 20),
		"profile": _debug_adaptive_profile(0, 0, "medium"),
		"personality": default_personality.duplicate(true),
	}
	match scenario_id:
		"work_focus":
			now = work_time
			mode = "活泼"
			context["state"] = _debug_calm_state(now)
			context["state"]["memory"]["last_action_at"] = now - 80
			context["memory"] = _debug_adaptive_memory(["tease_success"], 85, 20, 80)
			context["personality"] = _debug_adaptive_personality(95, 20, 25, 90)
		"hungry_care":
			context["state"]["hunger"] = 76
			context["memory"] = _debug_adaptive_memory(["feed_success"], 85, 80, 10)
			context["personality"] = _debug_adaptive_personality(70, 20, 25, 60)
		"low_mood_play":
			context["state"]["mood"] = 45
			context["memory"] = _debug_adaptive_memory(["tease_success"], 85, 10, 80)
			context["personality"] = _debug_adaptive_personality(95, 25, 20, 90)
		"rest_boundary":
			now = rest_time
			mode = "活泼"
			context["state"] = _debug_calm_state(now)
			context["state"]["energy"] = 80
		"busy_guard":
			context["busy"] = true
			context["memory"] = _debug_adaptive_memory(["tease_success"], 85, 10, 80)
			context["personality"] = _debug_adaptive_personality(95, 25, 20, 90)
		"mischief_forced":
			mode = "捣乱"
			context["state"]["memory"]["last_interaction_at"] = now
			context["personality"] = _debug_adaptive_personality(40, 90, 20, 35)
		"profile_low_interrupt":
			mode = "活泼"
			context["state"]["memory"]["last_action_at"] = now - 130
			context["memory"] = _debug_adaptive_memory([], 20, 0, 0)
			context["profile"] = _debug_adaptive_profile(10, 10, "low", "安静", "entertainment")
			context["personality"] = _debug_adaptive_personality(45, 20, 85, 20)
		"profile_playful":
			mode = "活泼"
			context["state"]["mood"] = 38
			context["memory"] = _debug_adaptive_memory([], 25, 0, 0)
			context["profile"] = _debug_adaptive_profile(10, 90, "high", "活泼", "entertainment", ["tease_success"])
			context["personality"] = _debug_adaptive_personality(50, 20, 50, 40)
		"profile_care":
			mode = "活泼"
			context["state"]["hunger"] = 78
			context["memory"] = _debug_adaptive_memory([], 25, 0, 0)
			context["profile"] = _debug_adaptive_profile(90, 10, "medium", "活泼", "entertainment", ["feed_success"])
			context["personality"] = _debug_adaptive_personality(50, 20, 50, 40)
		"profile_work_protected":
			now = work_time
			mode = "活泼"
			context["state"] = _debug_calm_state(now)
			context["state"]["memory"]["last_action_at"] = now - 130
			context["memory"] = _debug_adaptive_memory([], 25, 0, 0)
			context["profile"] = _debug_adaptive_profile(20, 95, "high", "活泼", "work", ["tease_success"])
			context["personality"] = _debug_adaptive_personality(55, 20, 40, 60)
		"profile_rest_protected":
			now = rest_time
			mode = "活泼"
			context["state"] = _debug_calm_state(now)
			context["state"]["energy"] = 80
			context["profile"] = _debug_adaptive_profile(20, 95, "high", "活泼", "rest", ["tease_success"])
			context["personality"] = _debug_adaptive_personality(70, 20, 30, 70)
	var scenario_brain = BehaviorBrainScript.new()
	scenario_brain.configure(behavior_config)
	scenario_brain.set_skin_behavior_profile(skin_behavior_profile)
	scenario_brain.set_mode(mode)
	if scenario_id == "mischief_forced":
		scenario_brain.request_forced_mischief("grab", 0.0, 6.0, now)
	var decision = scenario_brain.decide(context, now)
	var period = scenario_brain.period_for(now)
	scenario_brain.free()
	var passed = _scenario_passed(scenario_id, decision)
	return {
		"id": scenario_id,
		"label": _scenario_label(scenario_id),
		"passed": passed,
		"expected": _scenario_expected(scenario_id),
		"mode": mode,
		"period": period,
		"context": _compact_behavior_context(context),
		"decision": decision,
	}


func _scenario_passed(scenario_id: String, decision: Dictionary) -> bool:
	var decision_type = str(decision.get("type", ""))
	var decision_name = str(decision.get("name", ""))
	var intent = decision.get("intent", {})
	if typeof(intent) != TYPE_DICTIONARY:
		intent = {}
	match scenario_id:
		"work_focus":
			return decision_type == "none"
		"hungry_care":
			return decision_type == "prompt" and decision_name == "hungry" and str(intent.get("type", "")) == "care_request"
		"low_mood_play":
			return decision_type == "prompt" and decision_name == "play" and str(intent.get("type", "")) == "play_request"
		"rest_boundary":
			return decision_type == "action" and decision_name == "sleep"
		"busy_guard":
			return decision_type == "none" and str(decision.get("reason", "")) == "busy"
		"mischief_forced":
			return decision_type == "mischief" and decision_name == "grab" and str(intent.get("source", "")) == "forced"
		"profile_low_interrupt":
			return decision_type == "none" and str(decision.get("reason", "")) == "attention_cooldown" and _decision_has_profile_reason(decision) and float(decision.get("adaptation", {}).get("cooldown_multiplier", 1.0)) > 1.0
		"profile_playful":
			return decision_type == "prompt" and decision_name == "play" and str(intent.get("type", "")) == "play_request" and _decision_has_profile_reason(decision)
		"profile_care":
			return decision_type == "prompt" and decision_name == "hungry" and str(intent.get("type", "")) == "care_request" and _decision_has_profile_reason(decision)
		"profile_work_protected":
			return decision_type == "none" and str(decision.get("reason", "")) == "attention_cooldown" and _decision_has_profile_reason(decision)
		"profile_rest_protected":
			return decision_type == "action" and decision_name == "sleep" and _decision_has_profile_reason(decision)
	return false


func _scenario_label(scenario_id: String) -> String:
	var labels = {
		"work_focus": "工作时段低打扰",
		"hungry_care": "饥饿照料",
		"low_mood_play": "低心情陪玩",
		"rest_boundary": "休息边界",
		"busy_guard": "忙碌保护",
		"mischief_forced": "强制捣乱",
		"profile_low_interrupt": "长期低打扰用户",
		"profile_playful": "长期高陪玩用户",
		"profile_care": "长期高照料用户",
		"profile_work_protected": "工作时段长期偏好保护",
		"profile_rest_protected": "休息时段保护",
	}
	return str(labels.get(scenario_id, scenario_id))


func _scenario_expected(scenario_id: String) -> String:
	var expected = {
		"work_focus": "工作时段不缩短基础冷却，返回 none",
		"hungry_care": "feed_success 偏好使 hunger=76 触发 hungry prompt",
		"low_mood_play": "高玩心和陪玩偏好使 mood=45 触发 play prompt",
		"rest_boundary": "休息时段且 energy<85 进入 sleep",
		"busy_guard": "busy=true 时返回 none/busy",
		"mischief_forced": "捣乱强制首轮返回 mischief grab 且 source=forced",
		"profile_low_interrupt": "低打扰画像拉长活泼模式主动冷却，返回 none",
		"profile_playful": "高陪玩画像提高低心情陪玩提示阈值",
		"profile_care": "高照料画像温和降低饥饿提示阈值",
		"profile_work_protected": "长期偏好不能绕过工作时段基础冷却",
		"profile_rest_protected": "长期偏好不能绕过休息时段睡眠边界",
	}
	return str(expected.get(scenario_id, ""))


func _decision_has_profile_reason(decision: Dictionary) -> bool:
	var adaptation = decision.get("adaptation", {})
	if typeof(adaptation) != TYPE_DICTIONARY:
		return false
	var reasons = adaptation.get("reasons", [])
	if typeof(reasons) != TYPE_ARRAY:
		return false
	for reason in reasons:
		if str(reason).find("profile") >= 0:
			return true
	return false


func _event_count() -> int:
	if event_store != null and event_store.has_method("all_events"):
		return event_store.all_events().size()
	return 0


func _debug_calm_state(now_unix: int) -> Dictionary:
	return {
		"version": 2,
		"mood": 70,
		"hunger": 60,
		"energy": 80,
		"affection": 30,
		"last_decay_at": now_unix,
		"memory": {
			"last_interaction_at": 0,
			"last_interaction_kind": "",
			"last_feed_at": 0,
			"last_play_at": 0,
			"last_prompt_at": 0,
			"last_action_at": 0,
			"interaction_counts": {},
		},
	}


func _debug_adaptive_memory(favorites: Array, familiarity: int, care_score: int, play_score: int) -> Dictionary:
	return {
		"version": 1,
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": "活泼",
			"favorite_period": "entertainment",
		},
		"relationship": {
			"level": "close" if familiarity >= 70 else "familiar",
			"familiarity": familiarity,
			"care_score": care_score,
			"play_score": play_score,
		},
		"short_term": {
			"counts": {},
			"recent_kinds": favorites,
		},
	}


func _debug_adaptive_profile(care_tendency: int, play_tendency: int, interruption_tolerance: String, favorite_mode := "活泼", favorite_period := "entertainment", favorites := []) -> Dictionary:
	return {
		"version": 1,
		"updated_at": 0,
		"lifetime": {
			"total_events": 0,
			"counts": {},
			"mode_counts": {},
			"period_counts": {},
			"care_score": care_tendency,
			"play_score": play_tendency,
			"disruption_score": 0,
			"last_event_at": 0,
			"processed_event_ids": [],
		},
		"trends": {},
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": favorite_mode,
			"favorite_period": favorite_period,
			"care_tendency": care_tendency,
			"play_tendency": play_tendency,
			"interruption_tolerance": interruption_tolerance,
		},
		"relationship": {
			"level": "familiar",
			"familiarity": 45,
			"care_score": care_tendency,
			"play_score": play_tendency,
		},
	}


func _debug_adaptive_personality(playfulness: int, mischief: int, patience: int, clinginess: int) -> Dictionary:
	return {
		"version": 1,
		"archetype": "playful",
		"tone": "short_cute",
		"traits": {
			"playfulness": playfulness,
			"mischief": mischief,
			"patience": patience,
			"clinginess": clinginess,
		},
		"dialogue_style": {
			"max_chars": 28,
			"use_status_numbers": false,
			"avoid_repeating_recent": true,
		},
	}


func _debug_unix_for_local_datetime(year: int, month: int, day: int, hour: int) -> int:
	var utc_unix = int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": 0,
		"second": 0,
	}))
	var time_zone = Time.get_time_zone_from_system()
	var bias_minutes = int(time_zone.get("bias", 0)) if typeof(time_zone) == TYPE_DICTIONARY else 0
	return utc_unix - bias_minutes * 60


func _compact_behavior_context(context: Dictionary) -> Dictionary:
	return {
		"mode": str(context.get("mode", "")),
		"period": str(context.get("period", "")),
		"busy": bool(context.get("busy", false)),
		"physics_state": str(context.get("physics_state", "")),
		"mini_game": str(context.get("mini_game", "")),
		"peek_mode": bool(context.get("peek_mode", false)),
		"skin_id": str(context.get("skin_id", "")),
		"state": context.get("state", {}).duplicate(true) if typeof(context.get("state", {})) == TYPE_DICTIONARY else {},
		"memory": context.get("memory", {}).duplicate(true) if typeof(context.get("memory", {})) == TYPE_DICTIONARY else {},
		"profile": context.get("profile", {}).duplicate(true) if typeof(context.get("profile", {})) == TYPE_DICTIONARY else {},
		"personality": context.get("personality", {}).duplicate(true) if typeof(context.get("personality", {})) == TYPE_DICTIONARY else {},
	}
