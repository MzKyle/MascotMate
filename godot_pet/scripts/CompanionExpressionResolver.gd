extends RefCounted

const CompanionIntent = preload("res://scripts/CompanionIntent.gd")


func resolve(intent_value, decision := {}) -> Dictionary:
	var intent = CompanionIntent.sanitize(intent_value)
	var decision_type = str(decision.get("type", ""))
	var decision_name = str(decision.get("name", ""))
	var result := {
		"version": 1,
		"intent": intent,
		"bubble": {},
		"action": "",
		"capability": "",
		"effect": "",
		"mini_game": "",
		"mischief": "",
		"state_delta": {},
		"record": {},
		"meta": {},
	}
	match str(intent.get("type", "")):
		"social_response":
			_apply_social_response(result, intent)
		"care_request":
			_apply_care_request(result, intent, decision)
		"play_request":
			_apply_play_request(result, intent, decision)
		"rest_request":
			_apply_rest_request(result, intent, decision)
		"ambient":
			_apply_ambient(result, intent, decision)
		"mischief":
			_apply_mischief(result, intent, decision)
	if result["bubble"].is_empty() and decision_type == "prompt":
		_set_bubble(result, "auto_prompt:%s" % decision_name, str(decision.get("message", "")), 2.4)
	return result


func _apply_social_response(result: Dictionary, intent: Dictionary) -> void:
	var name = str(intent.get("name", ""))
	var meta = intent.get("meta", {})
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {}
	var fallback = str(meta.get("fallback_text", _default_social_text(name)))
	var seconds = float(meta.get("seconds", _default_social_seconds(name)))
	_set_bubble(result, str(meta.get("expression_key", name)), fallback, seconds)
	result["effect"] = str(meta.get("effect", _default_social_effect(name)))
	result["capability"] = str(meta.get("capability", _default_social_capability(name)))


func _apply_care_request(result: Dictionary, intent: Dictionary, decision: Dictionary) -> void:
	var name = str(intent.get("name", ""))
	if name == "hungry":
		_set_bubble(result, "auto_prompt:hungry", str(decision.get("message", "有点饿了。")), 2.4)
		result["effect"] = "note"


func _apply_play_request(result: Dictionary, intent: Dictionary, decision: Dictionary) -> void:
	var name = str(intent.get("name", ""))
	if name in ["low_mood", "invite"]:
		_set_bubble(result, "auto_prompt:play", str(decision.get("message", "要不要玩一会儿？")), 1.8)
		if str(decision.get("type", "")) == "action":
			result["action"] = "invite"
			result["meta"]["lock_seconds"] = 3.0


func _apply_rest_request(result: Dictionary, _intent: Dictionary, _decision: Dictionary) -> void:
	result["action"] = "sleep"
	result["capability"] = "sleeping"
	result["state_delta"] = {"sleep_tick": true}
	result["meta"]["lock_seconds"] = 24.0


func _apply_ambient(result: Dictionary, intent: Dictionary, decision: Dictionary) -> void:
	var name = str(intent.get("name", ""))
	if name == "walk":
		result["action"] = "walk"
		result["meta"]["lock_seconds"] = 8.0
	elif name == "idle":
		result["action"] = "idle"
		result["capability"] = "resting"
		result["meta"]["clear_auto_lock"] = true
	elif name == "edge_peek":
		result["action"] = "edge"
		result["meta"]["lock_seconds"] = 8.0
	elif name == "companion_pose":
		result["action"] = "companion"
		result["capability"] = "companion"
		result["meta"]["lock_seconds"] = 6.0
	elif name == "footprint":
		result["effect"] = "footprint"
	else:
		var decision_name = str(decision.get("name", ""))
		if decision_name != "":
			result["action"] = decision_name


func _apply_mischief(result: Dictionary, intent: Dictionary, decision: Dictionary) -> void:
	var name = str(intent.get("name", ""))
	if name == "grab_mouse" or str(decision.get("name", "")) == "grab":
		result["mischief"] = "grab"
	else:
		result["effect"] = "footprint"


func _set_bubble(result: Dictionary, key: String, fallback_text: String, seconds: float) -> void:
	var clean_key = key.strip_edges()
	var text = fallback_text.strip_edges()
	if clean_key == "" and text == "":
		return
	result["bubble"] = {
		"key": clean_key,
		"fallback_text": text,
		"seconds": max(0.1, seconds),
	}


func _default_social_text(name: String) -> String:
	var values = {
		"pet_head": "摸摸头。",
		"poke_body": "戳到了。",
		"grab_start": "抱起来啦。",
		"release_soft": "轻轻放下。",
		"throw_fast": "飞出去啦！",
		"peek_exit": "被发现啦。",
		"feed_success": "吃到啦。",
		"tease_start": "来逗我呀。",
		"tease_success": "嘿嘿，别挠啦。",
		"tease_done": "玩够啦。",
		"mode_changed": "{mode}模式。",
	}
	return str(values.get(name, ""))


func _default_social_seconds(name: String) -> float:
	if name in ["tease_start", "tease_success"]:
		return 1.4
	if name == "tease_done":
		return 1.3
	return 1.8


func _default_social_effect(name: String) -> String:
	if name == "pet_head":
		return "heart"
	if name == "poke_body":
		return "jiggle"
	return ""


func _default_social_capability(name: String) -> String:
	if name == "feed_success":
		return "feeding"
	return ""
