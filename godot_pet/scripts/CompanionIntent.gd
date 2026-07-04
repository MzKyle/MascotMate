extends RefCounted

const VERSION := 1
const VALID_TYPES := [
	"care_request",
	"rest_request",
	"play_request",
	"social_response",
	"ambient",
	"mischief",
]
const VALID_INTERRUPTION_LEVELS := ["none", "low", "medium", "high"]


static func make(intent_type: String, intent_name: String, reason := "", priority := 50, cooldown_key := "", interruption_level := "low", source := "rule", constraints := {}, meta := {}) -> Dictionary:
	var clean_type = intent_type.strip_edges()
	var clean_name = intent_name.strip_edges()
	var clean_level = interruption_level.strip_edges()
	if not clean_level in VALID_INTERRUPTION_LEVELS:
		clean_level = "low"
	var intent := {
		"version": VERSION,
		"type": clean_type,
		"name": clean_name,
		"key": "%s:%s" % [clean_type, clean_name] if clean_type != "" and clean_name != "" else "",
		"source": source.strip_edges(),
		"priority": clampi(int(priority), 0, 100),
		"reason": reason.strip_edges(),
		"interruption_level": clean_level,
		"cooldown_key": cooldown_key.strip_edges(),
		"constraints": _dictionary_or_empty(constraints),
		"meta": _dictionary_or_empty(meta),
	}
	return sanitize(intent)


static func social_response(name: String, reason := "", priority := 70, meta := {}) -> Dictionary:
	return make("social_response", name, reason, priority, "response:%s" % name, "low", "user", {
		"allow_bubble": true,
		"allow_action": false,
		"allow_effect": true,
	}, meta)


static func sanitize(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return make("ambient", "unknown", "invalid intent", 0, "", "none", "fallback")
	var clean_type = str(value.get("type", "")).strip_edges()
	var clean_name = str(value.get("name", "")).strip_edges()
	var clean_key = str(value.get("key", "")).strip_edges()
	if clean_key == "" and clean_type != "" and clean_name != "":
		clean_key = "%s:%s" % [clean_type, clean_name]
	var level = str(value.get("interruption_level", "low")).strip_edges()
	if not level in VALID_INTERRUPTION_LEVELS:
		level = "low"
	return {
		"version": VERSION,
		"type": clean_type,
		"name": clean_name,
		"key": clean_key,
		"source": str(value.get("source", "rule")).strip_edges(),
		"priority": clampi(int(value.get("priority", 50)), 0, 100),
		"reason": str(value.get("reason", "")).strip_edges(),
		"interruption_level": level,
		"cooldown_key": str(value.get("cooldown_key", "")).strip_edges(),
		"constraints": _dictionary_or_empty(value.get("constraints", {})),
		"meta": _dictionary_or_empty(value.get("meta", {})),
	}


static func is_valid(value) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var intent = sanitize(value)
	return str(intent.get("type", "")) in VALID_TYPES and str(intent.get("name", "")) != "" and str(intent.get("key", "")) != ""


static func key_for(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var intent = sanitize(value)
	return str(intent.get("key", ""))


static func _dictionary_or_empty(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return {}
