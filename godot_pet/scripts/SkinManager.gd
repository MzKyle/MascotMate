extends Node

signal skins_changed
signal skin_selected(skin_id)

const DEFAULT_SKIN_ID := "classic_shinchan"
const DEFAULT_SKIN_PATH := "res://assets/skins/classic_shinchan/skin.json"
const CORE_CAPABILITIES := ["resting", "locomotion", "falling", "held", "edge"]
const DEFAULT_PERSONALITY := {
	"version": 1,
	"archetype": "playful",
	"tone": "short_cute",
	"traits": {
		"playfulness": 70,
		"mischief": 35,
		"patience": 60,
		"clinginess": 45,
	},
	"favorite_intents": [],
	"dialogue_style": {
		"max_chars": 28,
		"use_status_numbers": false,
		"avoid_repeating_recent": true,
	},
}

var repo_root := ""
var config_dir := ""
var user_skin_root := ""
var legacy_manifest := {}
var skins_by_id := {}
var current_skin := {}
var current_frame_root := ""


func configure(root: String, user_config_dir: String, fallback_manifest: Dictionary) -> void:
	repo_root = root
	config_dir = user_config_dir
	user_skin_root = config_dir.path_join("skins")
	legacy_manifest = fallback_manifest.duplicate(true)
	reload_skins()


func reload_skins() -> void:
	skins_by_id = {}
	_load_builtin_default()
	_load_skin_directory(repo_root.path_join("skins"), "packaged")
	_load_skin_directory(user_skin_root, "user")
	emit_signal("skins_changed")


func list_skins() -> Array:
	var result := []
	for skin_id in skins_by_id.keys():
		result.append(skins_by_id[skin_id].duplicate(true))
	result.sort_custom(func(a, b): return str(a.get("name", a.get("id", ""))) < str(b.get("name", b.get("id", ""))))
	return result


func has_skin(skin_id: String) -> bool:
	return skins_by_id.has(skin_id)


func select_skin(skin_id: String) -> bool:
	var next_id = skin_id if skins_by_id.has(skin_id) else DEFAULT_SKIN_ID
	if not skins_by_id.has(next_id):
		return false
	current_skin = skins_by_id[next_id].duplicate(true)
	current_frame_root = str(current_skin.get("_frame_root_abs", ""))
	emit_signal("skin_selected", str(current_skin.get("id", next_id)))
	return true


func selected_skin_id() -> String:
	return str(current_skin.get("id", DEFAULT_SKIN_ID))


func selected_skin_name() -> String:
	return str(current_skin.get("name", selected_skin_id()))


func selected_personality() -> Dictionary:
	return _normalized_personality(current_skin.get("personality", {}))


func delete_user_skin(skin_id: String) -> bool:
	if not skins_by_id.has(skin_id):
		return false
	var skin = skins_by_id[skin_id]
	if str(skin.get("_kind", "")) != "user":
		return false
	var path = str(skin.get("_skin_path", "")).get_base_dir()
	if path == "" or path == user_skin_root:
		return false
	if not DirAccess.dir_exists_absolute(path):
		return false
	var err = OS.move_to_trash(path)
	if err != OK:
		return false
	reload_skins()
	return true


func _load_builtin_default() -> void:
	var loaded = _load_skin_file(DEFAULT_SKIN_PATH, "builtin")
	if loaded.is_empty():
		loaded = _normalized_skin(_legacy_default_skin(), DEFAULT_SKIN_PATH, "builtin")
	_add_skin(loaded)


func _load_skin_directory(root: String, kind: String) -> void:
	if root == "" or not DirAccess.dir_exists_absolute(root):
		return
	var dir = DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name = dir.get_next()
		if name == "":
			break
		if name.begins_with(".") or not dir.current_is_dir():
			continue
		var skin_path = root.path_join(name).path_join("skin.json")
		if FileAccess.file_exists(skin_path):
			var skin = _load_skin_file(skin_path, kind)
			if not skin.is_empty():
				_add_skin(skin)
	dir.list_dir_end()


func _load_skin_file(path: String, kind: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return _normalized_skin(parsed, path, kind)


func _normalized_skin(source: Dictionary, path: String, kind: String) -> Dictionary:
	var skin = source.duplicate(true)
	if not skin.has("schema_version"):
		skin["schema_version"] = int(skin.get("version", 1))
	if str(skin.get("id", "")) == "":
		return {}
	if typeof(skin.get("actions", {})) != TYPE_DICTIONARY:
		return {}
	if not skin.has("capabilities") or typeof(skin["capabilities"]) != TYPE_DICTIONARY:
		skin["capabilities"] = {}
	if not skin.has("fallbacks") or typeof(skin["fallbacks"]) != TYPE_DICTIONARY:
		skin["fallbacks"] = {}
	if not skin.has("metadata") or typeof(skin["metadata"]) != TYPE_DICTIONARY:
		skin["metadata"] = {}
	var metadata: Dictionary = skin["metadata"]
	metadata["package_version"] = str(metadata.get("package_version", "1.0.0"))
	if not metadata.has("authors") or typeof(metadata["authors"]) != TYPE_ARRAY:
		metadata["authors"] = []
	if not skin.has("license") or typeof(skin["license"]) != TYPE_DICTIONARY:
		skin["license"] = {"type": str(skin.get("license", "unknown"))}
	var license: Dictionary = skin["license"]
	license["type"] = str(license.get("type", "unknown"))
	license["summary"] = str(license.get("summary", license.get("type", "unknown")))
	license["redistributable"] = bool(license.get("redistributable", false))
	if not skin.has("source") or typeof(skin["source"]) != TYPE_DICTIONARY:
		skin["source"] = {}
	if not skin.has("behavior_profile") or typeof(skin["behavior_profile"]) != TYPE_DICTIONARY:
		skin["behavior_profile"] = {}
	var personality_source = skin.get("personality", {})
	if (typeof(personality_source) != TYPE_DICTIONARY or personality_source.is_empty()) and typeof(skin["behavior_profile"]) == TYPE_DICTIONARY:
		personality_source = skin["behavior_profile"].get("personality", {})
	skin["personality"] = _normalized_personality(personality_source)
	var report = _load_import_report(path)
	if not report.is_empty():
		skin["import_report"] = report
		metadata["compatibility_level"] = str(report.get("compatibility_level", metadata.get("compatibility_level", "minimal")))
		metadata["compatibility_score"] = int(report.get("compatibility_score", metadata.get("compatibility_score", 0)))
		metadata["capability_coverage"] = report.get("capability_coverage", _capability_coverage(skin))
		metadata["missing_capabilities"] = report.get("missing_capabilities", _missing_capabilities(skin))
	else:
		var score = _compatibility_score(skin)
		metadata["compatibility_score"] = int(metadata.get("compatibility_score", score))
		metadata["compatibility_level"] = str(metadata.get("compatibility_level", _compatibility_level(score)))
		metadata["capability_coverage"] = metadata.get("capability_coverage", _capability_coverage(skin))
		metadata["missing_capabilities"] = metadata.get("missing_capabilities", _missing_capabilities(skin))
	skin["_kind"] = kind
	skin["_skin_path"] = path
	skin["_frame_root_abs"] = _resolve_frame_root(str(skin.get("frame_root", "")), path)
	return skin


func _load_import_report(skin_path: String) -> Dictionary:
	var report_path = skin_path.get_base_dir().path_join("import_report.json")
	if not FileAccess.file_exists(report_path):
		return {}
	var file = FileAccess.open(report_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _capability_coverage(skin: Dictionary) -> Dictionary:
	var coverage := {}
	var capabilities = skin.get("capabilities", {})
	for capability in CORE_CAPABILITIES:
		var candidates = capabilities.get(capability, []) if typeof(capabilities) == TYPE_DICTIONARY else []
		coverage[capability] = typeof(candidates) == TYPE_ARRAY and not candidates.is_empty()
	return coverage


func _missing_capabilities(skin: Dictionary) -> Array:
	var missing := []
	var coverage = _capability_coverage(skin)
	for capability in CORE_CAPABILITIES:
		if not bool(coverage.get(capability, false)):
			missing.append(capability)
	return missing


func _compatibility_score(skin: Dictionary) -> int:
	var score := 100
	score -= _missing_capabilities(skin).size() * 14
	var actions = skin.get("actions", {})
	if typeof(actions) != TYPE_DICTIONARY or actions.is_empty():
		score = min(score, 20)
	return clampi(score, 0, 100)


func _compatibility_level(score: int) -> String:
	if score >= 90:
		return "excellent"
	if score >= 72:
		return "good"
	if score >= 45:
		return "partial"
	return "minimal"


func _resolve_frame_root(frame_root: String, manifest_path: String) -> String:
	if frame_root.begins_with("$repo/"):
		return repo_root.path_join(frame_root.substr(6)).simplify_path()
	if frame_root.begins_with("$config/"):
		return config_dir.path_join(frame_root.substr(8)).simplify_path()
	if frame_root.is_absolute_path() or frame_root.begins_with("res://") or frame_root.begins_with("user://"):
		return frame_root
	var base_dir = manifest_path.get_base_dir()
	return base_dir.path_join(frame_root).simplify_path()


func _add_skin(skin: Dictionary) -> void:
	var skin_id = str(skin.get("id", ""))
	if skin_id != "":
		skins_by_id[skin_id] = skin


func _default_personality() -> Dictionary:
	return DEFAULT_PERSONALITY.duplicate(true)


func _normalized_personality(source) -> Dictionary:
	var result = _default_personality()
	if typeof(source) != TYPE_DICTIONARY:
		return result
	result["version"] = max(1, int(source.get("version", result["version"])))
	var archetype = str(source.get("archetype", result["archetype"])).strip_edges()
	if archetype != "":
		result["archetype"] = archetype
	var tone = str(source.get("tone", result["tone"])).strip_edges()
	if tone != "":
		result["tone"] = tone
	var traits = source.get("traits", {})
	if typeof(traits) == TYPE_DICTIONARY:
		for key in result["traits"].keys():
			result["traits"][key] = clampi(int(traits.get(key, result["traits"][key])), 0, 100)
	var favorite_intents := []
	var source_favorites = source.get("favorite_intents", [])
	if typeof(source_favorites) == TYPE_ARRAY:
		for item in source_favorites:
			var value = str(item).strip_edges()
			if value != "":
				favorite_intents.append(value)
	result["favorite_intents"] = favorite_intents
	var dialogue_style = source.get("dialogue_style", {})
	if typeof(dialogue_style) == TYPE_DICTIONARY:
		result["dialogue_style"]["max_chars"] = clampi(int(dialogue_style.get("max_chars", result["dialogue_style"]["max_chars"])), 8, 80)
		result["dialogue_style"]["use_status_numbers"] = bool(dialogue_style.get("use_status_numbers", result["dialogue_style"]["use_status_numbers"]))
		result["dialogue_style"]["avoid_repeating_recent"] = bool(dialogue_style.get("avoid_repeating_recent", result["dialogue_style"]["avoid_repeating_recent"]))
	return result


func _legacy_default_skin() -> Dictionary:
	var actions = legacy_manifest.get("actions", {})
	return {
		"schema_version": 1,
		"version": 1,
		"id": DEFAULT_SKIN_ID,
		"name": "蜡笔小新默认皮肤",
		"preview": "",
		"frame_root": "$repo/resource_hd",
		"license": {"type": "local-personal-use"},
		"capabilities": {
			"resting": [{"action": "idle", "score": 100}],
			"locomotion": [
				{"action": "walk_left", "score": 100, "direction": "left"},
				{"action": "walk_right", "score": 100, "direction": "right"},
			],
			"falling": [{"action": "fall", "score": 100}],
			"held": [{"action": "idle", "score": 80}],
			"sleeping": [{"action": "sleep", "score": 100}],
			"feeding": [{"action": "eat", "score": 100}],
			"playful": [{"action": "pipi", "score": 100}],
			"mischief": [{"action": "mischief_grab", "score": 100}],
			"edge": [{"action": "walk_left", "score": 80}, {"action": "walk_right", "score": 80}],
			"reaction": [{"action": "idle", "score": 50}],
		},
		"fallbacks": {
			"locomotion": "resting",
			"falling": "resting",
			"held": "resting",
			"sleeping": "resting",
			"feeding": "playful",
			"playful": "resting",
			"mischief": "playful",
			"edge": "locomotion",
			"reaction": "resting",
		},
		"actions": actions,
		"_kind": "builtin",
		"_skin_path": DEFAULT_SKIN_PATH,
		"_frame_root_abs": repo_root.path_join("resource_hd"),
	}
