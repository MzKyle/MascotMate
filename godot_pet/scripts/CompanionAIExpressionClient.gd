extends Node

const DEFAULT_ENDPOINT := "http://127.0.0.1:8765"
const ALLOWED_KEYS := [
	"pet_head",
	"feed_success",
	"tease_success",
	"auto_prompt:hungry",
	"auto_prompt:play",
]
const ALLOWED_RESPONSE_KEYS := ["text", "seconds", "emotion", "safety"]
const RECENT_STATUS_LIMIT := 10

var enabled := false
var provider := "local_stub"
var endpoint := DEFAULT_ENDPOINT
var timeout_ms := 800
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
	recent_results = []


func status() -> Dictionary:
	var result = last_status.duplicate(true)
	result["health"] = health_status.duplicate(true)
	result["recent_results"] = recent_results.duplicate(true)
	result["source_stats"] = _source_stats()
	result["fallback_reasons"] = _fallback_reasons()
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

	var request_node = HTTPRequest.new()
	request_node.timeout = max(0.05, float(timeout_ms) / 1000.0)
	add_child(request_node)
	var payload = _request_payload(key, context, local_result, default_seconds)
	var headers = PackedStringArray(["Content-Type: application/json"])
	var err = request_node.request(_expression_url(), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request_node.queue_free()
		_update_status(local_result.get("source", "local"), "request_start_failed", false, key)
		local_result["fallback_reason"] = "request_start_failed"
		return local_result
	var completed = await request_node.request_completed
	request_node.queue_free()
	var result = int(completed[0])
	var response_code = int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_update_status(local_result.get("source", "local"), "http_failed", false, key)
		local_result["fallback_reason"] = "http_failed"
		return local_result
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var ai_result = _validate_response(parsed, local_result, context)
	_update_status(str(ai_result.get("source", "local")), str(ai_result.get("fallback_reason", "")), str(ai_result.get("source", "")) == "ai", key)
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


func _update_status(source: String, error: String, available: bool, key := "", record_result := true) -> void:
	last_status = {
		"enabled": enabled,
		"provider": provider,
		"endpoint": endpoint,
		"available": available,
		"last_source": source,
		"last_error": error,
	}
	if record_result and key != "":
		_record_result(key, source, error)


func _record_result(key: String, source: String, reason: String) -> void:
	recent_results.append({
		"key": key,
		"source": source,
		"fallback_reason": reason,
		"at": int(Time.get_unix_time_from_system()),
	})
	while recent_results.size() > RECENT_STATUS_LIMIT:
		recent_results.pop_front()


func _source_stats() -> Dictionary:
	var stats := {"ai": 0, "local": 0, "fallback": 0}
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
