extends Node

const DEFAULT_REST_ACTIONS := ["idle", "stand", "Stand"]

var skin := {}
var actions := {}
var capabilities := {}
var fallbacks := {}


func configure(skin_manifest: Dictionary) -> void:
	skin = skin_manifest.duplicate(true)
	actions = skin.get("actions", {})
	capabilities = skin.get("capabilities", {})
	fallbacks = skin.get("fallbacks", {})


func resolve(capability: String, constraints: Dictionary = {}) -> String:
	var visited := {}
	return _resolve_inner(capability, constraints, visited)


func _resolve_inner(capability: String, constraints: Dictionary, visited: Dictionary) -> String:
	if capability == "" or visited.has(capability):
		return _default_action()
	visited[capability] = true

	var direct = _best_candidate(capability, constraints)
	if direct != "":
		return direct

	if actions.has(capability):
		return capability

	var fallback = str(fallbacks.get(capability, ""))
	if fallback != "":
		var resolved = _resolve_inner(fallback, constraints, visited)
		if resolved != "":
			return resolved

	if capability != "resting":
		var resting = _resolve_inner("resting", constraints, visited)
		if resting != "":
			return resting

	return _default_action()


func _best_candidate(capability: String, constraints: Dictionary) -> String:
	var candidates = capabilities.get(capability, [])
	if typeof(candidates) != TYPE_ARRAY:
		return ""

	var best_action := ""
	var best_score := -INF
	var desired_direction = str(constraints.get("direction", ""))
	var preferred_action = str(constraints.get("preferred", ""))

	for candidate in candidates:
		var action_id := ""
		var score := 0.0
		var candidate_direction := ""
		if typeof(candidate) == TYPE_STRING:
			action_id = str(candidate)
			score = 50.0
		elif typeof(candidate) == TYPE_DICTIONARY:
			action_id = str(candidate.get("action", ""))
			score = float(candidate.get("score", 50.0))
			candidate_direction = str(candidate.get("direction", ""))
		else:
			continue

		if action_id == "" or not actions.has(action_id):
			continue
		if desired_direction != "" and candidate_direction != "":
			score += 40.0 if desired_direction == candidate_direction else -35.0
		if preferred_action != "" and preferred_action == action_id:
			score += 25.0
		if score > best_score:
			best_action = action_id
			best_score = score

	return best_action


func _default_action() -> String:
	for action_id in DEFAULT_REST_ACTIONS:
		if actions.has(action_id):
			return action_id
	for action_id in actions.keys():
		return str(action_id)
	return ""
