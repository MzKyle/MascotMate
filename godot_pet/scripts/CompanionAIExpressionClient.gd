extends Node

const DEFAULT_ENDPOINT := "http://127.0.0.1:8765"
const CACHE_TTL_SECONDS := 600
const MAX_CACHE_ENTRIES := 48
const ALLOWED_KEYS := [
	"pet_head",
	"poke_body",
	"grab_start",
	"release_soft",
	"throw_fast",
	"peek_exit",
	"feed_success",
	"tease_start",
	"tease_success",
	"tease_done",
	"auto_prompt:hungry",
	"auto_prompt:play",
]
const ALLOWED_RESPONSE_KEYS := ["text", "seconds", "emotion", "safety"]
const ALLOWED_SUMMARY_KEYS := [
	"favorite_interactions",
	"favorite_mode",
	"favorite_period",
	"care_tendency",
	"play_tendency",
	"interruption_tolerance",
	"confidence",
	"safety",
]
const VALID_SUMMARY_INTERACTIONS := [
	"pet_head",
	"poke_body",
	"grab_start",
	"release_soft",
	"throw_fast",
	"peek_enter",
	"peek_exit",
	"feed_start",
	"feed_success",
	"tease_start",
	"tease_success",
]
const VALID_SUMMARY_MODES := ["", "安静", "活泼", "捣乱"]
const VALID_SUMMARY_PERIODS := ["", "work", "entertainment", "rest"]
const VALID_INTERRUPTION_TOLERANCE := ["low", "medium", "high"]
const RECENT_STATUS_LIMIT := 10

var enabled := false
var provider := "local_stub"
var endpoint := DEFAULT_ENDPOINT
var timeout_ms := 800
var memory_summary_config := {
	"enabled": false,
	"provider": "local_stub",
	"timeout_ms": 1500,
	"min_events": 12,
	"min_interval_seconds": 86400,
}
var last_status := {
	"enabled": false,
	"provider": "local_stub",
	"endpoint": DEFAULT_ENDPOINT,
	"available": false,
	"last_source": "local",
	"last_error": "",
}
var health_status := {
	"checked_at": 0,
	"ok": false,
	"provider": "local_stub",
	"configured": false,
	"status": "not_checked",
}
var memory_summary_last_status := {
	"enabled": false,
	"provider": "local_stub",
	"available": false,
	"last_source": "disabled",
	"last_error": "disabled",
	"checked_at": 0,
	"last_summary_at": 0,
}
var expression_cache := {}
var expression_cache_order := []
var recent_results := []


func configure(values := {}) -> void:
	var config = _sanitize_config(values)
	enabled = bool(config.get("enabled", false))
	provider = str(config.get("provider", "local_stub"))
	timeout_ms = int(config.get("timeout_ms", 800))
	endpoint = OS.get_environment("MASCOTMATE_AI_EXPRESSION_URL").strip_edges()
	if endpoint == "":
		endpoint = DEFAULT_ENDPOINT
	last_status = {
		"enabled": enabled,
		"provider": provider,
		"endpoint": endpoint,
		"available": false,
		"last_source": "local",
		"last_error": "",
	}
	health_status = {
		"checked_at": 0,
		"ok": false,
		"provider": provider,
		"configured": false,
		"status": "not_checked",
	}
	expression_cache = {}
	expression_cache_order = []
	recent_results = []


func configure_memory_summary(values := {}) -> void:
	memory_summary_config = _sanitize_memory_summary_config(values)
	memory_summary_last_status = {
		"enabled": bool(memory_summary_config.get("enabled", false)),
		"provider": str(memory_summary_config.get("provider", "local_stub")),
		"available": false,
		"last_source": "disabled",
		"last_error": "disabled" if not bool(memory_summary_config.get("enabled", false)) else "not_checked",
		"checked_at": 0,
		"last_summary_at": 0,
	}


func status() -> Dictionary:
	var result = last_status.duplicate(true)
	result["health"] = health_status.duplicate(true)
	result["recent_results"] = recent_results.duplicate(true)
	result["source_stats"] = _source_stats()
	result["fallback_reasons"] = _fallback_reasons()
	result["cache"] = {
		"ttl_seconds": CACHE_TTL_SECONDS,
		"size": expression_cache_order.size(),
		"max_size": MAX_CACHE_ENTRIES,
	}
	result["memory_summary"] = memory_summary_status()
	return result


func memory_summary_status() -> Dictionary:
	var result = memory_summary_last_status.duplicate(true)
	result["config"] = memory_summary_config.duplicate(true)
	return result


func should_try(key: String) -> bool:
	return enabled and key in ALLOWED_KEYS


func resolve_expression(key: String, context: Dictionary, local_expression: Dictionary, fallback_text: String, default_seconds := 1.8):
	var local_result = _local_result(local_expression, fallback_text, default_seconds, "local")
	if not enabled:
		_update_status("local", "disabled", false, key)
		return local_result
	if not key in ALLOWED_KEYS:
		_update_status(local_result.get("source", "local"), "key_not_allowed", false, key)
		local_result["fallback_reason"] = "key_not_allowed"
		return local_result
	if not is_inside_tree():
		_update_status(local_result.get("source", "local"), "client_not_inside_tree", false, key)
		local_result["fallback_reason"] = "client_not_inside_tree"
		return local_result

	var cache_key = _cache_key(key, context, local_result)
	var cached = _cached_result(cache_key)
	if not cached.is_empty():
		_update_status("ai_cache", "", true, key, true, true, 0)
		return cached

	var started_at = Time.get_ticks_msec()
	var request_node = HTTPRequest.new()
	request_node.timeout = max(0.05, float(timeout_ms) / 1000.0)
	add_child(request_node)
	var payload = _request_payload(key, context, local_result, default_seconds)
	var headers = PackedStringArray(["Content-Type: application/json"])
	var err = request_node.request(_expression_url(), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		_update_status(local_result.get("source", "local"), "request_start_failed", false, key, true, false, _elapsed_ms(started_at))
		local_result["fallback_reason"] = "request_start_failed"
		return local_result
	var completed = await request_node.request_completed
	request_node.queue_free()
	var result = int(completed[0])
	var response_code = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_update_status(local_result.get("source", "local"), "http_failed", false, key, true, false, _elapsed_ms(started_at))
		local_result["fallback_reason"] = "http_failed"
		return local_result
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var ai_result = _validate_response(parsed, local_result, context)
	if str(ai_result.get("source", "")) == "ai":
		_store_cache(cache_key, ai_result)
	_update_status(str(ai_result.get("source", "local")), str(ai_result.get("fallback_reason", "")), str(ai_result.get("source", "")) == "ai", key, true, false, _elapsed_ms(started_at))
	return ai_result


func check_health():
	if not enabled:
		health_status = _health_result(false, false, "disabled")
		_update_status(str(last_status.get("last_source", "local")), "disabled", false, "", false)
		return health_status.duplicate(true)
	if not is_inside_tree():
		health_status = _health_result(false, false, "client_not_inside_tree")
		_update_status(str(last_status.get("last_source", "local")), "client_not_inside_tree", false, "", false)
		return health_status.duplicate(true)
	var request_node = HTTPRequest.new()
	request_node.timeout = max(0.05, float(timeout_ms) / 1000.0)
	add_child(request_node)
	var err = request_node.request(_health_url(), PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		request_node.queue_free()
		health_status = _health_result(false, false, "request_start_failed")
		_update_status(str(last_status.get("last_source", "local")), "health_request_start_failed", false, "", false)
		return health_status.duplicate(true)
	var completed = await request_node.request_completed
	request_node.queue_free()
	var result = int(completed[0])
	var response_code = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		health_status = _health_result(false, false, "http_failed")
		_update_status(str(last_status.get("last_source", "local")), "health_http_failed", false, "", false)
		return health_status.duplicate(true)
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		health_status = _health_result(false, false, "bad_json")
		_update_status(str(last_status.get("last_source", "local")), "health_bad_json", false, "", false)
		return health_status.duplicate(true)
	health_status = {
		"checked_at": int(Time.get_unix_time_from_system()),
		"ok": bool(parsed.get("ok", false)),
		"provider": str(parsed.get("provider", provider)),
		"configured": bool(parsed.get("configured", false)),
		"status": str(parsed.get("status", "unknown")),
	}
	_update_status(str(last_status.get("last_source", "local")), str(health_status.get("status", "")), bool(health_status.get("ok", false)) and bool(health_status.get("configured", false)), "", false)
	return health_status.duplicate(true)


func summarize_memory(payload: Dictionary, force := false):
	var config = memory_summary_config
	if not bool(config.get("enabled", false)):
		return _memory_summary_fallback("disabled")
	if not is_inside_tree():
		return _memory_summary_fallback("client_not_inside_tree")
	var recent_events = payload.get("recent_events", [])
	if typeof(recent_events) != TYPE_ARRAY:
		recent_events = []
	if not force and recent_events.size() < int(config.get("min_events", 12)):
		return _memory_summary_fallback("not_enough_events")
	var request_node = HTTPRequest.new()
	request_node.timeout = max(0.05, float(config.get("timeout_ms", 1500)) / 1000.0)
	add_child(request_node)
	var request_payload = payload.duplicate(true)
	request_payload["provider"] = str(config.get("provider", "local_stub"))
	var err = request_node.request(_memory_summary_url(), PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(request_payload))
	if err != OK:
		request_node.queue_free()
		return _memory_summary_fallback("request_start_failed")
	var completed = await request_node.request_completed
	request_node.queue_free()
	var result = int(completed[0])
	var response_code = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return _memory_summary_fallback("http_failed")
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var summary_result = _validate_memory_summary(parsed)
	_update_memory_summary_status(summary_result)
	return summary_result


func _validate_response(parsed, local_result: Dictionary, context := {}) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fallback(local_result, "bad_json")
	for key in parsed.keys():
		if not str(key) in ALLOWED_RESPONSE_KEYS:
			return _fallback(local_result, "unknown_field")
	if str(parsed.get("safety", "fallback")) != "ok":
		return _fallback(local_result, "safety_fallback")
	var text = _clean_text(str(parsed.get("text", "")))
	if text == "":
		return _fallback(local_result, "empty_text")
	if text.length() > _max_chars(context):
		return _fallback(local_result, "too_long")
	return {
		"text": text,
		"seconds": _clamp_seconds(parsed.get("seconds", local_result.get("seconds", 1.8))),
		"source": "ai",
		"emotion": _clean_text(str(parsed.get("emotion", "neutral"))),
		"fallback_reason": "",
		"cache_hit": false,
	}


func _validate_memory_summary(parsed) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return _memory_summary_fallback("bad_json")
	for key in parsed.keys():
		if not str(key) in ALLOWED_SUMMARY_KEYS:
			return _memory_summary_fallback("unknown_field")
	if str(parsed.get("safety", "fallback")) != "ok":
		return _memory_summary_fallback("safety_fallback")
	var confidence = clampi(int(parsed.get("confidence", 0)), 0, 100)
	var interactions = _clean_allowed_array(parsed.get("favorite_interactions", []), VALID_SUMMARY_INTERACTIONS, 3)
	var favorite_mode = str(parsed.get("favorite_mode", "")).strip_edges()
	if not favorite_mode in VALID_SUMMARY_MODES:
		return _memory_summary_fallback("invalid_mode")
	var favorite_period = str(parsed.get("favorite_period", "")).strip_edges()
	if not favorite_period in VALID_SUMMARY_PERIODS:
		return _memory_summary_fallback("invalid_period")
	var interruption_tolerance = str(parsed.get("interruption_tolerance", "medium")).strip_edges()
	if not interruption_tolerance in VALID_INTERRUPTION_TOLERANCE:
		return _memory_summary_fallback("invalid_interruption_tolerance")
	if confidence < 60:
		return _memory_summary_fallback("low_confidence")
	var summary = {
		"favorite_interactions": interactions,
		"favorite_mode": favorite_mode,
		"favorite_period": favorite_period,
		"care_tendency": clampi(int(parsed.get("care_tendency", 0)), 0, 100),
		"play_tendency": clampi(int(parsed.get("play_tendency", 0)), 0, 100),
		"interruption_tolerance": interruption_tolerance,
		"confidence": confidence,
	}
	return {
		"source": "ai",
		"fallback_reason": "",
		"summary": summary,
		"at": int(Time.get_unix_time_from_system()),
	}


func _sanitize_config(values) -> Dictionary:
	var result := {
		"enabled": false,
		"provider": "local_stub",
		"timeout_ms": 800,
	}
	if typeof(values) != TYPE_DICTIONARY:
		return result
	if values.has("enabled"):
		result["enabled"] = bool(values["enabled"])
	if values.has("provider"):
		var clean_provider = str(values["provider"])
		result["provider"] = clean_provider if clean_provider in ["local_stub", "openai_compatible"] else "local_stub"
	if values.has("timeout_ms"):
		result["timeout_ms"] = clampi(int(values["timeout_ms"]), 100, 5000)
	return result


func _sanitize_memory_summary_config(values) -> Dictionary:
	var result := {
		"enabled": false,
		"provider": "local_stub",
		"timeout_ms": 1500,
		"min_events": 12,
		"min_interval_seconds": 86400,
	}
	if typeof(values) != TYPE_DICTIONARY:
		return result
	if values.has("enabled"):
		result["enabled"] = bool(values["enabled"])
	if values.has("provider"):
		var clean_provider = str(values["provider"])
		result["provider"] = clean_provider if clean_provider in ["local_stub", "openai_compatible"] else "local_stub"
	if values.has("timeout_ms"):
		result["timeout_ms"] = clampi(int(values["timeout_ms"]), 100, 5000)
	if values.has("min_events"):
		result["min_events"] = clampi(int(values["min_events"]), 1, 200)
	if values.has("min_interval_seconds"):
		result["min_interval_seconds"] = clampi(int(values["min_interval_seconds"]), 60, 30 * 24 * 60 * 60)
	return result


func _request_payload(key: String, context: Dictionary, local_result: Dictionary, default_seconds: float) -> Dictionary:
	return {
		"key": key,
		"fallback_text": str(local_result.get("text", "")),
		"default_seconds": float(local_result.get("seconds", default_seconds)),
		"intent": context.get("intent", {}) if typeof(context.get("intent", {})) == TYPE_DICTIONARY else {},
		"state": context.get("state", {}) if typeof(context.get("state", {})) == TYPE_DICTIONARY else {},
		"memory": context.get("memory", {}) if typeof(context.get("memory", {})) == TYPE_DICTIONARY else {},
		"profile": context.get("profile", {}) if typeof(context.get("profile", {})) == TYPE_DICTIONARY else {},
		"personality": context.get("personality", {}) if typeof(context.get("personality", {})) == TYPE_DICTIONARY else {},
		"recent_expressions": context.get("recent_expression_texts", []) if typeof(context.get("recent_expression_texts", [])) == TYPE_ARRAY else [],
		"provider": provider,
	}


func _expression_url() -> String:
	return _base_endpoint() + "/v1/expression"


func _health_url() -> String:
	return _base_endpoint() + "/health"


func _memory_summary_url() -> String:
	return _base_endpoint() + "/v1/memory-summary"


func _base_endpoint() -> String:
	var base = endpoint
	while base.ends_with("/") and base.length() > 0:
		base = base.substr(0, base.length() - 1)
	return base


func _local_result(local_expression: Dictionary, fallback_text: String, default_seconds: float, reason: String) -> Dictionary:
	var found = bool(local_expression.get("found", false))
	var text = str(local_expression.get("text", fallback_text)).strip_edges()
	if text == "":
		text = fallback_text
	return {
		"text": text,
		"seconds": _clamp_seconds(local_expression.get("seconds", default_seconds)),
		"source": "local" if found else "fallback",
		"emotion": "",
		"fallback_reason": reason if not found else "",
	}


func _fallback(local_result: Dictionary, reason: String) -> Dictionary:
	var result = local_result.duplicate(true)
	result["source"] = "fallback" if str(result.get("source", "local")) != "local" else "local"
	result["fallback_reason"] = reason
	return result


func _update_status(source: String, error: String, available: bool, key := "", record_result := true, cache_hit := false, latency_ms := 0) -> void:
	last_status = {
		"enabled": enabled,
		"provider": provider,
		"endpoint": endpoint,
		"available": available,
		"last_source": source,
		"last_error": error,
	}
	if record_result and key != "":
		_record_result(key, source, error, cache_hit, latency_ms)


func _record_result(key: String, source: String, reason: String, cache_hit := false, latency_ms := 0) -> void:
	recent_results.append({
		"key": key,
		"source": source,
		"fallback_reason": reason,
		"cache_hit": cache_hit,
		"latency_ms": max(0, int(latency_ms)),
		"at": int(Time.get_unix_time_from_system()),
	})
	while recent_results.size() > RECENT_STATUS_LIMIT:
		recent_results.pop_front()


func _source_stats() -> Dictionary:
	var stats := {"ai": 0, "ai_cache": 0, "local": 0, "fallback": 0}
	for item in recent_results:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var source = str(item.get("source", "fallback"))
		stats[source] = int(stats.get(source, 0)) + 1
	return stats


func _fallback_reasons() -> Array:
	var reasons := []
	for item in recent_results:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var reason = str(item.get("fallback_reason", "")).strip_edges()
		if reason != "":
			reasons.append({
				"key": str(item.get("key", "")),
				"reason": reason,
				"source": str(item.get("source", "")),
				"at": int(item.get("at", 0)),
			})
	return reasons


func _memory_summary_fallback(reason: String) -> Dictionary:
	var result = {
		"source": "fallback",
		"fallback_reason": reason,
		"summary": {},
		"at": int(Time.get_unix_time_from_system()),
	}
	_update_memory_summary_status(result)
	return result


func _update_memory_summary_status(result: Dictionary) -> void:
	var source = str(result.get("source", "fallback"))
	var reason = str(result.get("fallback_reason", ""))
	var now = int(Time.get_unix_time_from_system())
	memory_summary_last_status = {
		"enabled": bool(memory_summary_config.get("enabled", false)),
		"provider": str(memory_summary_config.get("provider", "local_stub")),
		"available": source == "ai",
		"last_source": source,
		"last_error": reason,
		"checked_at": now,
		"last_summary_at": now if source == "ai" else int(memory_summary_last_status.get("last_summary_at", 0)),
	}


func _cached_result(cache_key: String) -> Dictionary:
	if cache_key == "" or not expression_cache.has(cache_key):
		return {}
	var entry = expression_cache.get(cache_key, {})
	if typeof(entry) != TYPE_DICTIONARY:
		expression_cache.erase(cache_key)
		expression_cache_order.erase(cache_key)
		return {}
	var now = int(Time.get_unix_time_from_system())
	if now - int(entry.get("at", 0)) > CACHE_TTL_SECONDS:
		expression_cache.erase(cache_key)
		expression_cache_order.erase(cache_key)
		return {}
	var result = entry.get("result", {})
	if typeof(result) != TYPE_DICTIONARY:
		return {}
	result = result.duplicate(true)
	result["source"] = "ai_cache"
	result["cache_hit"] = true
	result["fallback_reason"] = ""
	return result


func _store_cache(cache_key: String, result: Dictionary) -> void:
	if cache_key == "" or str(result.get("source", "")) != "ai":
		return
	expression_cache[cache_key] = {
		"at": int(Time.get_unix_time_from_system()),
		"result": result.duplicate(true),
	}
	expression_cache_order.erase(cache_key)
	expression_cache_order.append(cache_key)
	while expression_cache_order.size() > MAX_CACHE_ENTRIES:
		var oldest = expression_cache_order.pop_front()
		expression_cache.erase(oldest)


func _cache_key(key: String, context: Dictionary, local_result: Dictionary) -> String:
	var intent = context.get("intent", {}) if typeof(context) == TYPE_DICTIONARY else {}
	if typeof(intent) != TYPE_DICTIONARY:
		intent = {}
	var intent_key = str(intent.get("key", ""))
	if intent_key == "" and str(intent.get("type", "")) != "" and str(intent.get("name", "")) != "":
		intent_key = "%s:%s" % [str(intent.get("type", "")), str(intent.get("name", ""))]
	var state = context.get("state", {}) if typeof(context) == TYPE_DICTIONARY else {}
	if typeof(state) != TYPE_DICTIONARY:
		state = {}
	var recent = context.get("recent_expression_texts", []) if typeof(context) == TYPE_DICTIONARY else []
	if typeof(recent) != TYPE_ARRAY:
		recent = []
	var recent_tail := []
	var start = max(0, recent.size() - 3)
	for i in range(start, recent.size()):
		recent_tail.append(str(recent[i]))
	return "|".join([
		key,
		intent_key,
		_context_tone(context),
		_context_relationship_level(context),
		_state_bucket(state, "mood"),
		_state_bucket(state, "hunger"),
		_state_bucket(state, "energy"),
		_state_bucket(state, "affection"),
		str(local_result.get("text", "")),
		" / ".join(recent_tail),
	])


func _state_bucket(state: Dictionary, key: String) -> String:
	return "%s:%d" % [key, int(floor(float(state.get(key, 0)) / 10.0)) * 10]


func _context_tone(context) -> String:
	if typeof(context) != TYPE_DICTIONARY:
		return ""
	var tone = str(context.get("tone", "")).strip_edges()
	if tone != "":
		return tone
	var personality = context.get("personality", {})
	if typeof(personality) == TYPE_DICTIONARY:
		return str(personality.get("tone", "")).strip_edges()
	return ""


func _context_relationship_level(context) -> String:
	if typeof(context) != TYPE_DICTIONARY:
		return ""
	var level = str(context.get("relationship_level", "")).strip_edges()
	if level != "":
		return level
	var relationship = context.get("relationship", {})
	if typeof(relationship) == TYPE_DICTIONARY:
		return str(relationship.get("level", "")).strip_edges()
	return ""


func _elapsed_ms(started_at: int) -> int:
	return max(0, int(Time.get_ticks_msec()) - started_at)


func _clean_allowed_array(value, allowed: Array, limit: int) -> Array:
	var result := []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		var text = str(item).strip_edges()
		if text != "" and text in allowed and not text in result:
			result.append(text)
		if result.size() >= limit:
			break
	return result


func _health_result(ok: bool, configured: bool, status_text: String) -> Dictionary:
	return {
		"checked_at": int(Time.get_unix_time_from_system()),
		"ok": ok,
		"provider": provider,
		"configured": configured,
		"status": status_text,
	}


func _clean_text(text: String) -> String:
	var result = text.replace("\r", " ").replace("\n", " ").strip_edges()
	var cleaned := ""
	for i in range(result.length()):
		var code = result.unicode_at(i)
		if code >= 32:
			cleaned += result.substr(i, 1)
	return cleaned.strip_edges()


func _max_chars(context) -> int:
	if typeof(context) != TYPE_DICTIONARY:
		return 28
	var personality = context.get("personality", {})
	if typeof(personality) != TYPE_DICTIONARY:
		return 28
	var style = personality.get("dialogue_style", {})
	if typeof(style) != TYPE_DICTIONARY:
		return 28
	return clampi(int(style.get("max_chars", 28)), 8, 80)


func _clamp_seconds(value) -> float:
	return clampf(float(value), 0.5, 5.0)
