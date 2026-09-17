extends SceneTree

const StateStoreScript = preload("res://scripts/StateStore.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const SkinManagerScript = preload("res://scripts/SkinManager.gd")
const PetSpriteScript = preload("res://scripts/PetSprite.gd")
const PetPhysicsScript = preload("res://scripts/PetPhysics.gd")
const MainScript = preload("res://scripts/Main.gd")
const PetWindowControllerScript = preload("res://scripts/PetWindowController.gd")
const ConfigStoreScript = preload("res://scripts/ConfigStore.gd")
const FeedbackEffectsScript = preload("res://scripts/FeedbackEffects.gd")
const MiniGamesScript = preload("res://scripts/MiniGames.gd")
const SkinCatalogClientScript = preload("res://scripts/SkinCatalogClient.gd")
const SkinStoreBridgeScript = preload("res://scripts/SkinStoreBridge.gd")
const CompanionConsoleBridgeScript = preload("res://scripts/CompanionConsoleBridge.gd")
const CompanionEventStoreScript = preload("res://scripts/CompanionEventStore.gd")
const CompanionMemoryScript = preload("res://scripts/CompanionMemory.gd")
const CompanionLongTermProfileScript = preload("res://scripts/CompanionLongTermProfile.gd")
const CompanionAIExpressionClientScript = preload("res://scripts/CompanionAIExpressionClient.gd")
const TestSupport = preload("res://tests/TestSupport.gd")

const FIXED_ENTERTAINMENT_TIME := 1761998400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var repo_root = TestSupport.repo_root()
	var config_dir = TestSupport.config_dir()
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for runtime smoke tests.")
		return

	var window_controller = PetWindowControllerScript.new()
	root_node.add_child(window_controller)
	await process_frame
	window_controller.configure(root_node, root_node)
	var window_state = window_controller.debug_state()
	for key in ["transparent_window", "mouse_passthrough_enabled", "borderless", "always_on_top", "window_transparent", "viewport_transparent_bg", "position", "size"]:
		if not window_state.has(key):
			_fail("PetWindowController debug_state missing key %s: %s" % [key, JSON.stringify(window_state)])
			return

	var event_store = CompanionEventStoreScript.new()
	root_node.add_child(event_store)
	event_store.configure(config_dir)
	event_store.record_event("pet_head", "user", {"mode": "smoke", "period": "entertainment", "skin_id": "test_skin"}, {}, ["social"], {}, {}, FIXED_ENTERTAINMENT_TIME + 10)
	event_store.record_event("feed_success", "user", {"mode": "smoke", "period": "entertainment", "skin_id": "test_skin"}, {}, ["care"], {}, {}, FIXED_ENTERTAINMENT_TIME + 20)
	event_store.record_event("tease_success", "user", {"mode": "smoke", "period": "entertainment", "skin_id": "test_skin"}, {}, ["play"], {}, {}, FIXED_ENTERTAINMENT_TIME + 30)
	var memory_store = CompanionMemoryScript.new()
	root_node.add_child(memory_store)
	memory_store.configure(config_dir, event_store)
	memory_store.refresh(FIXED_ENTERTAINMENT_TIME + 40)
	memory_store.record_expression("pet_head", "runtime expression", FIXED_ENTERTAINMENT_TIME + 41)
	var profile_store = CompanionLongTermProfileScript.new()
	root_node.add_child(profile_store)
	profile_store.configure(config_dir, event_store, memory_store)
	profile_store.refresh(FIXED_ENTERTAINMENT_TIME + 50)
	var ai_client = CompanionAIExpressionClientScript.new()
	root_node.add_child(ai_client)
	ai_client.configure({"enabled": false, "provider": "local_stub", "timeout_ms": 800})

	var skin_manager = SkinManagerScript.new()
	root_node.add_child(skin_manager)
	skin_manager.configure(repo_root, config_dir, TestSupport.load_json("res://assets/actions.json"))
	if not skin_manager.select_skin("classic_shinchan"):
		_fail("Default skin could not be selected.")
		return
	var default_personality = skin_manager.selected_personality()
	if str(default_personality.get("tone", "")) != "short_cute" or int(default_personality.get("traits", {}).get("playfulness", 0)) != 70:
		_fail("SkinManager did not provide the default personality: %s" % JSON.stringify(default_personality))
		return
	skin_manager.current_skin.erase("personality")
	var fallback_personality = skin_manager.selected_personality()
	if str(fallback_personality.get("archetype", "")) != "playful" or int(fallback_personality.get("dialogue_style", {}).get("max_chars", 0)) != 28:
		_fail("SkinManager did not recover a missing personality: %s" % JSON.stringify(fallback_personality))
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

	var console_bridge = CompanionConsoleBridgeScript.new()
	root_node.add_child(console_bridge)
	await process_frame
	console_bridge.configure(repo_root, config_dir)
	var console_command := {"payload": {}}
	console_bridge.command_received.connect(func(command): console_command["payload"] = command)
	var console_command_file = FileAccess.open(config_dir.path_join("companion_console_command.json"), FileAccess.WRITE)
	if console_command_file == null:
		_fail("CompanionConsoleBridge command file could not be written.")
		return
	console_command_file.store_string(JSON.stringify({
		"command": "set_behavior_mode",
		"payload": {"mode": "活泼"},
		"nonce": "runtime-smoke-console",
	}))
	console_command_file = null
	console_bridge._poll_command()
	var emitted_console_command = console_command.get("payload", {})
	if str(emitted_console_command.get("command", "")) != "set_behavior_mode" or str(emitted_console_command.get("payload", {}).get("mode", "")) != "活泼":
		_fail("CompanionConsoleBridge did not emit the command payload: %s" % JSON.stringify(console_command))
		return
	if FileAccess.file_exists(config_dir.path_join("companion_console_command.json")):
		_fail("CompanionConsoleBridge did not remove the handled command file.")
		return


	var config_store = ConfigStoreScript.new()
	root_node.add_child(config_store)
	config_store.configure()
	config_store.set_dialogue_tone("calm")
	var behavior_config = TestSupport.load_json("res://assets/behavior.json")
	var state_store = StateStoreScript.new()
	root_node.add_child(state_store)
	await process_frame
	state_store.state["hunger"] = 60
	state_store.state["energy"] = 80
	state_store.state["mood"] = 70
	state_store.state["last_decay_at"] = FIXED_ENTERTAINMENT_TIME
	state_store.state["memory"] = {
		"last_interaction_at": 0,
		"last_interaction_kind": "",
		"last_feed_at": 0,
		"last_play_at": 0,
		"last_prompt_at": 0,
		"last_action_at": 0,
		"interaction_counts": {},
	}

	var main_debug = MainScript.new()
	main_debug.config_store = config_store
	main_debug.window_controller = window_controller
	main_debug.behavior_manifest = behavior_config
	main_debug.behavior_mode = "活泼"
	main_debug.state_store = state_store
	main_debug.companion_event_store = event_store
	main_debug.companion_memory = memory_store
	main_debug.companion_profile = profile_store
	main_debug.companion_ai_expression_client = ai_client
	main_debug.skin_manager = skin_manager
	main_debug.physics = PetPhysicsScript.new()
	main_debug.mini_games = MiniGamesScript.new()
	main_debug.brain = BehaviorBrainScript.new()
	main_debug.brain.configure(main_debug._behavior_config_with_app_overrides())
	main_debug.companion_debug_snapshot_path = config_dir.path_join("companion_debug_snapshot.json")
	main_debug.companion_scenario_result_path = config_dir.path_join("companion_scenario_result.json")
	main_debug.last_behavior_decision = {"type": "none", "reason": "busy", "retry_after": 2.0}
	main_debug.last_behavior_context = {"mode": "活泼", "busy": true}
	main_debug.dialogue_tone = "calm"
	main_debug.last_expression = {"key": "pet_head", "text": "AI说辛苦啦。", "source": "ai", "at": FIXED_ENTERTAINMENT_TIME}
	main_debug._write_companion_debug_snapshot()
	var debug_snapshot = TestSupport.load_json(main_debug.companion_debug_snapshot_path)
	if str(debug_snapshot.get("runtime", {}).get("behavior_mode", "")) != "活泼" or typeof(debug_snapshot.get("memory", {})) != TYPE_DICTIONARY or typeof(debug_snapshot.get("profile", {})) != TYPE_DICTIONARY or typeof(debug_snapshot.get("recent_events", [])) != TYPE_ARRAY:
		_fail("Main debug snapshot was incomplete: %s" % JSON.stringify(debug_snapshot))
		return
	if str(debug_snapshot.get("last_decision", {}).get("reason", "")) != "busy":
		_fail("Main debug snapshot did not include the last decision: %s" % JSON.stringify(debug_snapshot))
		return
	if str(debug_snapshot.get("last_expression", {}).get("source", "")) != "ai" or typeof(debug_snapshot.get("ai_expression", {})) != TYPE_DICTIONARY:
		_fail("Main debug snapshot did not include AI expression state: %s" % JSON.stringify(debug_snapshot))
		return
	if typeof(debug_snapshot.get("window", {})) != TYPE_DICTIONARY or not debug_snapshot.get("window", {}).has("transparent_window") or not debug_snapshot.get("window", {}).has("mouse_passthrough_enabled"):
		_fail("Main debug snapshot did not include window diagnostics: %s" % JSON.stringify(debug_snapshot))
		return
	if str(debug_snapshot.get("config", {}).get("dialogue_tone", "")) != "calm":
		_fail("Main debug snapshot did not include dialogue tone: %s" % JSON.stringify(debug_snapshot))
		return
	var ai_snapshot = debug_snapshot.get("ai_expression", {})
	if typeof(ai_snapshot.get("health", {})) != TYPE_DICTIONARY or typeof(ai_snapshot.get("source_stats", {})) != TYPE_DICTIONARY or typeof(ai_snapshot.get("fallback_reasons", [])) != TYPE_ARRAY:
		_fail("Main debug snapshot did not include AI diagnostics: %s" % JSON.stringify(debug_snapshot))
		return
	if typeof(debug_snapshot.get("ai_memory_summary", {})) != TYPE_DICTIONARY or typeof(debug_snapshot.get("config", {}).get("ai_memory_summary", {})) != TYPE_DICTIONARY:
		_fail("Main debug snapshot did not include AI memory summary diagnostics: %s" % JSON.stringify(debug_snapshot))
		return
	main_debug._on_companion_console_command({
		"command": "set_adaptation",
		"payload": {"enabled": true, "strength": "subtle"},
	})
	var updated_adaptation = config_store.app_config().get("behavior_adaptation", {})
	if not bool(updated_adaptation.get("enabled", false)) or str(updated_adaptation.get("strength", "")) != "subtle":
		_fail("Main console adaptation command did not update config: %s" % JSON.stringify(config_store.get_config()))
		return
	main_debug._on_companion_console_command({
		"command": "set_ai_expression",
		"payload": {"enabled": false, "provider": "openai_compatible", "timeout_ms": 500},
	})
	var updated_ai_config = config_store.app_config().get("ai_expression", {})
	if bool(updated_ai_config.get("enabled", true)) or str(updated_ai_config.get("provider", "")) != "openai_compatible" or int(updated_ai_config.get("timeout_ms", 0)) != 500:
		_fail("Main console AI expression command did not update config: %s" % JSON.stringify(config_store.get_config()))
		return
	main_debug._on_companion_console_command({
		"command": "set_ai_memory_summary",
		"payload": {"enabled": true, "provider": "local_stub", "timeout_ms": 1600, "min_events": 6, "min_interval_seconds": 900},
	})
	var updated_summary_config = config_store.app_config().get("ai_memory_summary", {})
	if not bool(updated_summary_config.get("enabled", false)) or int(updated_summary_config.get("min_events", 0)) != 6 or int(updated_summary_config.get("min_interval_seconds", 0)) != 900:
		_fail("Main console AI memory summary command did not update config: %s" % JSON.stringify(config_store.get_config()))
		return
	await main_debug._on_companion_console_command({"command": "check_ai_health"})
	if str(ai_client.status().get("health", {}).get("status", "")) != "disabled":
		_fail("Main console AI health command did not update disabled health: %s" % JSON.stringify(ai_client.status()))
		return
	main_debug._on_companion_console_command({"command": "set_behavior_mode", "payload": {"mode": "捣乱"}})
	if main_debug.behavior_mode != "捣乱":
		_fail("Main console mode command did not change behavior mode.")
		return
	main_debug._on_companion_console_command({"command": "set_dialogue_tone", "payload": {"tone": "short_cute"}})
	if main_debug.dialogue_tone != "short_cute" or str(config_store.app_config().get("dialogue_tone", "")) != "short_cute":
		_fail("Main console dialogue tone command did not update config: %s" % JSON.stringify(config_store.get_config()))
		return
	main_debug._on_companion_console_command({
		"command": "set_adaptation",
		"payload": {"enabled": true, "strength": "visible"},
	})

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
	var compact_size = pet_sprite.compact_window_size()
	var padded_size = pet_sprite.padded_window_size()
	if compact_size.x >= padded_size.x or compact_size.y >= padded_size.y:
		_fail("PetSprite compact window was not smaller than padded window: compact=%s padded=%s" % [str(compact_size), str(padded_size)])
		return
	pet_sprite.position = pet_sprite.compact_pet_position(Vector2(compact_size))
	var visible_rect = pet_sprite.visible_rect()
	var visible_window_rect = Rect2(pet_sprite.position + visible_rect.position, visible_rect.size)
	if visible_window_rect.position.x < -0.5 or visible_window_rect.position.y < -0.5:
		_fail("PetSprite compact visible rect starts outside the window: %s" % str(visible_window_rect))
		return
	if visible_window_rect.position.x + visible_window_rect.size.x > float(compact_size.x) + 0.5 or visible_window_rect.position.y + visible_window_rect.size.y > float(compact_size.y) + 0.5:
		_fail("PetSprite compact visible rect exceeds the window: %s in %s" % [str(visible_window_rect), str(compact_size)])
		return

	var feedback = FeedbackEffectsScript.new()
	root_node.add_child(feedback)
	await process_frame
	feedback.configure(repo_root, pet_sprite)
	feedback.set_window_size(Vector2(padded_size))
	var feedback_requests := {"count": 0, "seconds": 0.0}
	feedback.temporary_window_extent_requested.connect(func(seconds): feedback_requests["count"] = int(feedback_requests["count"]) + 1; feedback_requests["seconds"] = max(float(feedback_requests["seconds"]), float(seconds)))
	feedback.show_bubble("测试气泡", 0.4)
	if int(feedback_requests["count"]) != 1 or float(feedback_requests["seconds"]) < 0.4:
		_fail("Feedback bubble did not request temporary window extent.")
		return
	if feedback.bubble == null or not feedback.bubble.visible:
		_fail("Feedback bubble did not become visible.")
		return
	feedback.spawn_heart()
	if int(feedback_requests["count"]) < 2:
		_fail("Feedback heart did not request temporary window extent.")
		return

	var mini_games = MiniGamesScript.new()
	root_node.add_child(mini_games)
	await process_frame
	mini_games.configure(repo_root, pet_sprite)
	var tease_events := {"count": 0, "finished": ""}
	mini_games.tease_success.connect(func(count, _direction): tease_events["count"] = int(count))
	mini_games.game_finished.connect(func(name): tease_events["finished"] = str(name))
	mini_games.start_tease()
	if mini_games.active != "tease":
		_fail("MiniGames did not enter tease mode.")
		return
	var pet_rect = pet_sprite.pet_rect()
	var tease_point = pet_sprite.to_global(pet_rect.position + pet_rect.size * 0.5)
	for _i in range(3):
		mini_games.tease_cooldown = 0.0
		mini_games._register_tease_sample(tease_point, Vector2(260, 0))
	if int(tease_events["count"]) != 3 or str(tease_events["finished"]) != "tease" or mini_games.active != "":
		_fail("MiniGames tease mode did not finish after three interactions: %s active=%s" % [JSON.stringify(tease_events), mini_games.active])
		return
	var feed_events := {"success": false, "finished": ""}
	mini_games.feed_success.connect(func(): feed_events["success"] = true)
	mini_games.game_finished.connect(func(name): feed_events["finished"] = str(name))
	mini_games.start_feed()
	if mini_games.active != "feed" or mini_games.food == null:
		_fail("MiniGames did not enter feed mode.")
		return
	var mouth_rect = pet_sprite.mouth_rect()
	mini_games.food.position = pet_sprite.to_global(mouth_rect.position + mouth_rect.size * 0.5)
	mini_games._check_food_hit()
	if not bool(feed_events["success"]) or str(feed_events["finished"]) != "feed" or mini_games.active != "":
		_fail("MiniGames feed mode did not emit success and finish: %s active=%s" % [JSON.stringify(feed_events), mini_games.active])
		return


	state_store.flush_save()
	print("Godot runtime smoke passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
