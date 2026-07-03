extends SceneTree

const StateStoreScript = preload("res://scripts/StateStore.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const SkinManagerScript = preload("res://scripts/SkinManager.gd")
const PetSpriteScript = preload("res://scripts/PetSprite.gd")
const MainScript = preload("res://scripts/Main.gd")
const SkinCatalogClientScript = preload("res://scripts/SkinCatalogClient.gd")
const SkinStoreBridgeScript = preload("res://scripts/SkinStoreBridge.gd")

const FIXED_ENTERTAINMENT_TIME := 1761998400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	var config_dir = OS.get_environment("CRAYON_PET_CONFIG_DIR")
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for smoke tests.")
		return

	var state_store = StateStoreScript.new()
	root_node.add_child(state_store)
	await process_frame
	state_store.state["hunger"] = 84
	state_store.state["energy"] = 70
	state_store.state["mood"] = 70
	state_store.state["last_decay_at"] = FIXED_ENTERTAINMENT_TIME - 3600
	state_store.state["memory"] = {
		"last_interaction_at": 0,
		"last_interaction_kind": "",
		"last_feed_at": 0,
		"last_play_at": 0,
		"last_prompt_at": 0,
		"last_action_at": 0,
		"interaction_counts": {},
	}

	var brain = BehaviorBrainScript.new()
	root_node.add_child(brain)
	brain.configure(_load_json("res://assets/behavior.json"))
	brain.set_mode("活泼")
	var decision = brain.decide({
		"busy": false,
		"state": state_store.snapshot(),
		"state_store": state_store,
	}, FIXED_ENTERTAINMENT_TIME)
	if str(decision.get("type", "")) != "prompt" or str(decision.get("name", "")) != "hungry":
		_fail("BehaviorBrain did not produce the expected hungry prompt: %s" % JSON.stringify(decision))
		return

	var skin_manager = SkinManagerScript.new()
	root_node.add_child(skin_manager)
	skin_manager.configure(repo_root, config_dir, _load_json("res://assets/actions.json"))
	if not skin_manager.select_skin("classic_shinchan"):
		_fail("Default skin could not be selected.")
		return

	var catalog_client = SkinCatalogClientScript.new()
	root_node.add_child(catalog_client)
	catalog_client.configure(repo_root, config_dir)
	var catalog_entries = catalog_client.load_fallback_catalog()
	if catalog_entries.is_empty():
		_fail("Skin catalog fallback did not load any entries.")
		return
	var external_seen := false
	var installable_entry := {}
	for entry in catalog_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("source_type", "")) == "external_browser":
			external_seen = true
		if str(entry.get("source_type", "")) in ["curated_package", "local_package"] and installable_entry.is_empty():
			installable_entry = entry
	if not external_seen:
		_fail("Skin catalog fallback did not include external Shimeji entries.")
		return
	if installable_entry.is_empty():
		_fail("Skin catalog fallback did not include installable entries.")
		return
	var download_result := {"path": "", "failure": ""}
	catalog_client.skin_downloaded.connect(func(_skin_id, path): download_result["path"] = path)
	catalog_client.skin_download_failed.connect(func(_skin_id, message): download_result["failure"] = message)
	catalog_client.download_skin(installable_entry)
	if str(download_result["path"]) == "":
		_fail("Skin catalog fallback download validation failed: %s" % str(download_result["failure"]))
		return

	var skin_store_bridge = SkinStoreBridgeScript.new()
	root_node.add_child(skin_store_bridge)
	await process_frame
	skin_store_bridge.configure(repo_root, config_dir)
	var requested_skin := {"id": ""}
	skin_store_bridge.skin_requested.connect(func(skin_id): requested_skin["id"] = skin_id)
	DirAccess.make_dir_recursive_absolute(config_dir)
	var command_file = FileAccess.open(config_dir.path_join("skin_store_command.json"), FileAccess.WRITE)
	if command_file == null:
		_fail("SkinStoreBridge command file could not be written.")
		return
	command_file.store_string(JSON.stringify({
		"command": "select_skin",
		"skin_id": "classic_shinchan",
		"nonce": "runtime-smoke",
	}))
	command_file = null
	skin_store_bridge._poll_command()
	if str(requested_skin["id"]) != "classic_shinchan":
		_fail("SkinStoreBridge did not emit the requested skin id.")
		return
	skin_manager.reload_skins()
	if not skin_manager.select_skin(str(requested_skin["id"])):
		_fail("SkinStoreBridge requested skin could not be selected.")
		return

	var pet_sprite = PetSpriteScript.new()
	root_node.add_child(pet_sprite)
	await process_frame
	pet_sprite.configure_skin(skin_manager.current_skin, skin_manager.current_frame_root)
	if not pet_sprite.play("idle"):
		_fail("PetSprite could not play idle.")
		return
	var after_first_play = pet_sprite.cache_info()
	if int(after_first_play.get("misses", 0)) != 1:
		_fail("PetSprite cache miss count after first play was unexpected.")
		return
	if not pet_sprite.play("idle"):
		_fail("PetSprite could not replay idle.")
		return
	var after_second_play = pet_sprite.cache_info()
	if int(after_second_play.get("hits", 0)) < 1:
		_fail("PetSprite cache did not record a hit on replay.")
		return
	if pet_sprite.current_used_rect.size.x <= 0.0 or pet_sprite.current_used_rect.size.y <= 0.0:
		_fail("PetSprite current used_rect is empty.")
		return

	state_store.flush_save()
	print("Godot runtime smoke passed.")
	quit(0)


func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Missing JSON: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Invalid JSON: %s" % path)
		return {}
	return parsed


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
