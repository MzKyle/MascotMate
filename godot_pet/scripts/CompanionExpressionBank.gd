extends Node

const MAX_RECENT_TEXTS := 8
const DEFAULT_LINES := {
	"pet_head": [
		{"text": "摸摸头。"},
		{"text": "再摸一下也可以。"},
		{"text": "今天也摸摸头。", "tones": ["short_cute"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["pet_head"]},
	],
	"poke_body": [
		{"text": "戳到了。"},
		{"text": "哎呀，痒痒的。"},
		{"text": "又戳我啦。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["poke_body"]},
	],
	"grab_start": [
		{"text": "抱起来啦。"},
		{"text": "要带我去哪呀？"},
		{"text": "又要带我走呀？", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["grab_start"]},
	],
	"release_soft": [
		{"text": "轻轻放下。"},
		{"text": "落地成功。"},
		{"text": "放得很稳。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["release_soft"]},
	],
	"throw_fast": [
		{"text": "飞出去啦！"},
		{"text": "哇，太快啦！"},
		{"text": "你又把我甩飞啦！", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["throw_fast"]},
	],
	"peek_exit": [
		{"text": "被发现啦。"},
		{"text": "我只是看一眼。"},
	],
	"feed_success": [
		{"text": "吃到啦。"},
		{"text": "好吃。"},
		{"text": "你知道我想吃这个。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["feed_success"]},
	],
	"tease_start": [
		{"text": "来逗我呀。", "seconds": 1.4},
		{"text": "我准备好啦。", "seconds": 1.4},
		{"text": "今天也来玩。", "seconds": 1.4, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
	],
	"tease_success": [
		{"text": "嘿嘿，别挠啦。", "seconds": 1.4},
		{"text": "抓不到我吧。", "seconds": 1.4},
		{"text": "你越来越会逗我啦。", "seconds": 1.4, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
	],
	"tease_done": [
		{"text": "玩够啦。", "seconds": 1.3},
		{"text": "休息一下。", "seconds": 1.3},
	],
	"mode_changed": [
		{"text": "{mode}模式。"},
		{"text": "切到{mode}啦。"},
	],
	"auto_prompt:hungry": [
		{"text": "有点饿了。", "seconds": 2.4},
		{"text": "饭团还在吗？", "seconds": 2.4},
		{"text": "我有点想吃饭团。", "seconds": 2.4, "tones": ["short_cute"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["feed_success"]},
	],
	"auto_prompt:play": [
		{"text": "要不要玩一会儿？", "seconds": 1.8},
		{"text": "陪我玩一下吧。", "seconds": 1.8},
		{"text": "今天也陪我玩一下？", "seconds": 1.8, "tones": ["short_cute"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
	],
}

var recent_texts := []


func resolve(key: String, context := {}, fallback_text := "", default_seconds := 1.8) -> Dictionary:
	var clean_key = key.strip_edges()
	var candidates = DEFAULT_LINES.get(clean_key, [])
	if typeof(candidates) != TYPE_ARRAY or candidates.is_empty():
		var fallback = _render_template(fallback_text, context)
		_remember_text(fallback)
		return {"found": false, "key": clean_key, "text": fallback, "seconds": float(default_seconds)}
	var candidate = _select_candidate(candidates, context)
	var text = _render_template(_candidate_text(candidate), context)
	var seconds = _candidate_seconds(candidate, default_seconds)
	if text == "":
		text = _render_template(fallback_text, context)
	_remember_text(text)
	return {"found": true, "key": clean_key, "text": text, "seconds": seconds}


func reset_history() -> void:
	recent_texts = []


func _select_candidate(candidates: Array, context):
	var usable = _matching_candidates(candidates, context)
	var memory_recent_texts = _memory_recent_texts(context)
	for candidate in usable:
		var text = _render_template(_candidate_text(candidate), context)
		if text != "" and not text in recent_texts and not text in memory_recent_texts:
			return candidate
	for candidate in usable:
		var text = _render_template(_candidate_text(candidate), context)
		if text != "" and not text in memory_recent_texts:
			return candidate
	for candidate in usable:
		if _render_template(_candidate_text(candidate), context) != "":
			return candidate
	return usable[0] if usable.size() > 0 else candidates[0]


func _matching_candidates(candidates: Array, context) -> Array:
	var result := []
	for candidate in candidates:
		if _candidate_matches(candidate, context):
			result.append(candidate)
	if not result.is_empty():
		return result
	for candidate in candidates:
		if _candidate_has_conditions(candidate):
			continue
		result.append(candidate)
	if not result.is_empty():
		return result
	return candidates


func _candidate_matches(candidate, context) -> bool:
	if typeof(candidate) != TYPE_DICTIONARY:
		return true
	var tone = _context_tone(context)
	if not _matches_context_value(candidate, "tones", tone):
		return false
	if not _matches_context_value(candidate, "relationship_levels", _context_relationship_level(context)):
		return false
	if not _matches_context_value(candidate, "modes", _context_string(context, "mode")):
		return false
	if not _matches_context_value(candidate, "periods", _context_string(context, "period")):
		return false
	var required_favorites = _candidate_string_array(candidate, "favorite_interactions")
	if not required_favorites.is_empty():
		var favorites = _context_string_array(context, "favorite_interactions")
		var matched := false
		for item in required_favorites:
			if item in favorites:
				matched = true
				break
		if not matched:
			return false
	return true


func _candidate_has_conditions(candidate) -> bool:
	if typeof(candidate) != TYPE_DICTIONARY:
		return false
	for key in ["tones", "relationship_levels", "favorite_interactions", "modes", "periods"]:
		if candidate.has(key):
			return true
	return false


func _matches_context_value(candidate: Dictionary, field: String, value: String) -> bool:
	var allowed = _candidate_string_array(candidate, field)
	if allowed.is_empty():
		return true
	return value in allowed


func _candidate_string_array(candidate: Dictionary, field: String) -> Array:
	var result := []
	var values = candidate.get(field, [])
	if typeof(values) != TYPE_ARRAY:
		return result
	for item in values:
		var value = str(item).strip_edges()
		if value != "":
			result.append(value)
	return result


func _candidate_text(candidate) -> String:
	if typeof(candidate) == TYPE_DICTIONARY:
		return str(candidate.get("text", ""))
	return str(candidate)


func _candidate_seconds(candidate, default_seconds: float) -> float:
	if typeof(candidate) == TYPE_DICTIONARY and candidate.has("seconds"):
		return max(0.1, float(candidate["seconds"]))
	return max(0.1, default_seconds)


func _remember_text(text: String) -> void:
	if text == "":
		return
	recent_texts.append(text)
	while recent_texts.size() > MAX_RECENT_TEXTS:
		recent_texts.pop_front()


func _render_template(text: String, context) -> String:
	var source = text
	var values = context if typeof(context) == TYPE_DICTIONARY else {}
	var result := ""
	var cursor := 0
	while cursor < source.length():
		var open_index = source.find("{", cursor)
		if open_index < 0:
			result += source.substr(cursor)
			break
		result += source.substr(cursor, open_index - cursor)
		var close_index = source.find("}", open_index + 1)
		if close_index < 0:
			break
		var key = source.substr(open_index + 1, close_index - open_index - 1)
		result += str(values.get(key, ""))
		cursor = close_index + 1
	return result


func _context_string(context, key: String) -> String:
	if typeof(context) == TYPE_DICTIONARY:
		return str(context.get(key, "")).strip_edges()
	return ""


func _context_tone(context) -> String:
	var tone = _context_string(context, "tone")
	if tone != "":
		return tone
	if typeof(context) == TYPE_DICTIONARY:
		var personality = context.get("personality", {})
		if typeof(personality) == TYPE_DICTIONARY:
			return str(personality.get("tone", "")).strip_edges()
	return ""


func _context_relationship_level(context) -> String:
	var level = _context_string(context, "relationship_level")
	if level != "":
		return level
	if typeof(context) == TYPE_DICTIONARY:
		var relationship = context.get("relationship", {})
		if typeof(relationship) == TYPE_DICTIONARY:
			return str(relationship.get("level", "")).strip_edges()
	return ""


func _context_string_array(context, key: String) -> Array:
	var result := []
	if typeof(context) != TYPE_DICTIONARY:
		return result
	var values = context.get(key, [])
	if typeof(values) != TYPE_ARRAY:
		var memory = context.get("memory", {})
		if typeof(memory) == TYPE_DICTIONARY:
			var preferences = memory.get("preferences", {})
			if typeof(preferences) == TYPE_DICTIONARY:
				values = preferences.get(key, [])
	if typeof(values) != TYPE_ARRAY:
		return result
	for item in values:
		var value = str(item).strip_edges()
		if value != "":
			result.append(value)
	return result


func _memory_recent_texts(context) -> Array:
	var result = _context_string_array(context, "recent_expression_texts")
	if typeof(context) != TYPE_DICTIONARY:
		return result
	var memory = context.get("memory", {})
	if typeof(memory) != TYPE_DICTIONARY:
		return result
	var dialogue = memory.get("dialogue", {})
	if typeof(dialogue) != TYPE_DICTIONARY:
		return result
	var recent_lines = dialogue.get("recent_lines", [])
	if typeof(recent_lines) != TYPE_ARRAY:
		return result
	for item in recent_lines:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var text = str(item.get("text", "")).strip_edges()
		if text != "" and not text in result:
			result.append(text)
	return result
