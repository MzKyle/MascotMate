extends Node

const MAX_RECENT_TEXTS := 8
const DEFAULT_LINES := {
	"pet_head": [
		{"text": "摸摸头，辛苦啦。", "tones": ["gentle"]},
		{"text": "今天也很棒。", "tones": ["short_cute"]},
		{"text": "我在这儿，不着急。", "tones": ["calm"]},
		{"text": "多摸一会儿也可以。", "tones": ["gentle"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["pet_head"]},
		{"text": "你一摸头，我就充满电。", "tones": ["short_cute"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["pet_head"]},
		{"text": "慢慢来，我陪着你。", "tones": ["calm"], "relationship_levels": ["familiar", "close"], "favorite_interactions": ["pet_head"]},
		{"text": "摸摸头，辛苦啦。"},
		{"text": "今天也很棒。"},
	],
	"poke_body": [
		{"text": "轻轻戳一下就好。", "tones": ["gentle"]},
		{"text": "收到，小小提醒。", "tones": ["short_cute"]},
		{"text": "我在这儿，慢一点。", "tones": ["calm"]},
		{"text": "戳到了，也别太用力哦。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["poke_body"]},
		{"text": "轻轻戳一下就好。"},
	],
	"grab_start": [
		{"text": "抱起来啦，慢慢来。", "tones": ["gentle"]},
		{"text": "出发，今天也很棒。", "tones": ["short_cute"]},
		{"text": "我在这儿，不着急。", "tones": ["calm"]},
		{"text": "带我走也可以，稳一点就好。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["grab_start"]},
		{"text": "抱起来啦，慢慢来。"},
	],
	"release_soft": [
		{"text": "放得很稳，谢谢你。", "tones": ["gentle"]},
		{"text": "稳稳落地，谢谢。", "tones": ["short_cute"]},
		{"text": "这样就很好。", "tones": ["calm"]},
		{"text": "放得很稳，谢谢你。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["release_soft"]},
		{"text": "放得很稳，谢谢你。"},
	],
	"throw_fast": [
		{"text": "有点快，慢一点也可以。", "tones": ["gentle"]},
		{"text": "哇，好快，接住啦。", "tones": ["short_cute"]},
		{"text": "先缓一缓，我没事。", "tones": ["calm"]},
		{"text": "下次轻一点，我会更安心。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["throw_fast"]},
		{"text": "有点快，慢一点也可以。"},
	],
	"peek_exit": [
		{"text": "我在这儿，陪你一下。", "tones": ["gentle"]},
		{"text": "被发现啦，打个招呼。", "tones": ["short_cute"]},
		{"text": "只是出来透口气。", "tones": ["calm"]},
		{"text": "我在这儿，陪你一下。"},
	],
	"feed_success": [
		{"text": "吃到啦，谢谢你。", "tones": ["gentle"]},
		{"text": "补充能量，开心。", "tones": ["short_cute"]},
		{"text": "暖暖的，刚刚好。", "tones": ["calm"]},
		{"text": "你记得我喜欢这个，谢谢。", "relationship_levels": ["familiar", "close"], "favorite_interactions": ["feed_success"]},
		{"text": "吃到啦，谢谢你。"},
	],
	"tease_start": [
		{"text": "要不要放松一下？", "seconds": 1.4, "tones": ["gentle"]},
		{"text": "来玩一小会儿。", "seconds": 1.4, "tones": ["short_cute"]},
		{"text": "轻轻玩一下就好。", "seconds": 1.4, "tones": ["calm"]},
		{"text": "今天也陪我玩一下？", "seconds": 1.4, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
		{"text": "要不要放松一下？", "seconds": 1.4},
	],
	"tease_success": [
		{"text": "笑一下，放松啦。", "seconds": 1.4, "tones": ["gentle"]},
		{"text": "今天也很棒，再来一下。", "seconds": 1.4, "tones": ["short_cute"]},
		{"text": "刚刚好，轻松一点。", "seconds": 1.4, "tones": ["calm"]},
		{"text": "你越来越会逗我开心啦。", "seconds": 1.4, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
		{"text": "笑一下，放松啦。", "seconds": 1.4},
	],
	"tease_done": [
		{"text": "休息一下，辛苦啦。", "seconds": 1.3, "tones": ["gentle"]},
		{"text": "玩得开心，充电完成。", "seconds": 1.3, "tones": ["short_cute"]},
		{"text": "到这里就好，慢慢来。", "seconds": 1.3, "tones": ["calm"]},
		{"text": "休息一下，辛苦啦。", "seconds": 1.3},
	],
	"mode_changed": [
		{"text": "已切到{mode}模式，我会配合你。", "tones": ["gentle"]},
		{"text": "{mode}模式，准备好啦。", "tones": ["short_cute"]},
		{"text": "{mode}模式，慢慢来。", "tones": ["calm"]},
		{"text": "已切到{mode}模式，我会配合你。"},
	],
	"auto_prompt:hungry": [
		{"text": "我有点饿了，要不要补点能量？", "seconds": 2.4, "tones": ["gentle"]},
		{"text": "要不要吃点东西？", "seconds": 2.4, "tones": ["short_cute"]},
		{"text": "有点饿，方便时再照顾我就好。", "seconds": 2.4, "tones": ["calm"]},
		{"text": "想吃一点，谢谢你记得我。", "seconds": 2.4, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["feed_success"]},
		{"text": "我有点饿了，要不要补点能量？", "seconds": 2.4},
	],
	"auto_prompt:play": [
		{"text": "要不要放松一下？", "seconds": 1.8, "tones": ["gentle"]},
		{"text": "要不要玩一小会儿？", "seconds": 1.8, "tones": ["short_cute"]},
		{"text": "休息一下也可以。", "seconds": 1.8, "tones": ["calm"]},
		{"text": "今天也陪我放松一下？", "seconds": 1.8, "relationship_levels": ["familiar", "close"], "favorite_interactions": ["tease_success"]},
		{"text": "要不要放松一下？", "seconds": 1.8},
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
