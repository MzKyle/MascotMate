extends Node

signal skins_changed
signal skin_selected(skin_id)

const DEFAULT_SKIN_ID := "classic_shinchan"
const DEFAULT_SKIN_PATH := "res://assets/skins/classic_shinchan/skin.json"

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
		loaded = _legacy_default_skin()
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
	if str(skin.get("id", "")) == "":
		return {}
	if typeof(skin.get("actions", {})) != TYPE_DICTIONARY:
		return {}
	if not skin.has("capabilities") or typeof(skin["capabilities"]) != TYPE_DICTIONARY:
		skin["capabilities"] = {}
	if not skin.has("fallbacks") or typeof(skin["fallbacks"]) != TYPE_DICTIONARY:
		skin["fallbacks"] = {}
	skin["_kind"] = kind
	skin["_skin_path"] = path
	skin["_frame_root_abs"] = _resolve_frame_root(str(skin.get("frame_root", "")), path)
	return skin


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


func _legacy_default_skin() -> Dictionary:
	var actions = legacy_manifest.get("actions", {})
	return {
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
