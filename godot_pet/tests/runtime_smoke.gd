extends SceneTree

const StateStoreScript = preload("res://scripts/StateStore.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const SkinManagerScript = preload("res://scripts/SkinManager.gd")
const PetSpriteScript = preload("res://scripts/PetSprite.gd")
const MainScript = preload("res://scripts/Main.gd")
const FeedbackEffectsScript = preload("res://scripts/FeedbackEffects.gd")
const MiniGamesScript = preload("res://scripts/MiniGames.gd")
const SkinCatalogClientScript = preload("res://scripts/SkinCatalogClient.gd")
const SkinStoreBridgeScript = preload("res://scripts/SkinStoreBridge.gd")
const CompanionEventStoreScript = preload("res://scripts/CompanionEventStore.gd")
const CompanionMemoryScript = preload("res://scripts/CompanionMemory.gd")
const CompanionExpressionBankScript = preload("res://scripts/CompanionExpressionBank.gd")

const FIXED_ENTERTAINMENT_TIME := 1761998400
const FIXED_WORK_TIME := 1762164000
const FIXED_REST_TIME := 1762038000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var repo_root = ProjectSettings.globalize_path("res://..").simplify_path()
	var config_dir = OS.get_environment("CRAYON_PET_CONFIG_DIR")
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for smoke tests.")
		return

	var event_store = CompanionEventStoreScript.new()
	root_node.add_child(event_store)
	event_store.configure(config_dir)
	for i in range(205):
		event_store.record_event("event_%03d" % i, "test", {"mode": "smoke", "skin_id": "test_skin"}, {"index": i}, ["smoke"], {}, {}, FIXED_ENTERTAINMENT_TIME + i)
	var recent = event_store.recent_events(200)
	if recent.size() != 200 or str(recent[0].get("kind", "")) != "event_005" or str(recent[199].get("kind", "")) != "event_204":
		_fail("CompanionEventStore did not retain the newest 200 events: size=%d first=%s last=%s" % [
			recent.size(),
			str(recent[0].get("kind", "")) if recent.size() > 0 else "",
			str(recent[recent.size() - 1].get("kind", "")) if recent.size() > 0 else "",
		])
		return
	var corrupt_file = FileAccess.open(config_dir.path_join("companion_events.json"), FileAccess.WRITE)
	if corrupt_file == null:
		_fail("CompanionEventStore file could not be opened for corruption test.")
		return
	corrupt_file.store_string("{broken")
	corrupt_file = null
	event_store.configure(config_dir)
	event_store.record_event("after_corrupt", "test", {}, {}, [], {}, {}, FIXED_ENTERTAINMENT_TIME)
	var recovered = event_store.recent_events(1)
	if recovered.size() != 1 or str(recovered[0].get("kind", "")) != "after_corrupt":
		_fail("CompanionEventStore did not recover after invalid JSON: %s" % JSON.stringify(recovered))
		return
	var all_recovered_events = event_store.all_events()
	if all_recovered_events.size() != 1 or str(all_recovered_events[0].get("kind", "")) != "after_corrupt":
		_fail("CompanionEventStore all_events returned unexpected data: %s" % JSON.stringify(all_recovered_events))
		return

	event_store.record_event("pet_head", "user", {"mode": "活泼", "period": "entertainment", "skin_id": "test_skin"}, {}, ["social"], {}, {}, FIXED_ENTERTAINMENT_TIME + 10)
	event_store.record_event("feed_success", "user", {"mode": "活泼", "period": "entertainment", "skin_id": "test_skin"}, {}, ["care"], {}, {}, FIXED_ENTERTAINMENT_TIME + 20)
	event_store.record_event("tease_success", "user", {"mode": "活泼", "period": "entertainment", "skin_id": "test_skin"}, {}, ["play"], {}, {}, FIXED_ENTERTAINMENT_TIME + 30)
	var memory_store = CompanionMemoryScript.new()
	root_node.add_child(memory_store)
	memory_store.configure(config_dir, event_store)
	memory_store.refresh(FIXED_ENTERTAINMENT_TIME + 40)
	var memory_snapshot = memory_store.snapshot()
	var daily_counts = memory_snapshot.get("daily", {}).get("counts", {})
	var short_counts = memory_snapshot.get("short_term", {}).get("counts", {})
	if int(daily_counts.get("pet_head", 0)) != 1 or int(short_counts.get("feed_success", 0)) != 1 or int(short_counts.get("tease_success", 0)) != 1:
		_fail("CompanionMemory did not aggregate event counts: %s" % JSON.stringify(memory_snapshot))
		return
	var favorites = memory_snapshot.get("preferences", {}).get("favorite_interactions", [])
	if typeof(favorites) != TYPE_ARRAY or not favorites.has("pet_head") or not favorites.has("feed_success") or not favorites.has("tease_success"):
		_fail("CompanionMemory did not derive favorite interactions: %s" % JSON.stringify(memory_snapshot))
		return
	var relationship = memory_snapshot.get("relationship", {})
	if typeof(relationship) != TYPE_DICTIONARY or str(relationship.get("level", "")) != "familiar" or int(relationship.get("familiarity", 0)) < 25:
		_fail("CompanionMemory did not derive the expected relationship level: %s" % JSON.stringify(memory_snapshot))
		return
	memory_store.record_expression("pet_head", "今天也摸摸头。", FIXED_ENTERTAINMENT_TIME + 41)
	var memory_context = memory_store.expression_context({"mode": "活泼"})
	var recent_expression_texts = memory_context.get("recent_expression_texts", [])
	if typeof(recent_expression_texts) != TYPE_ARRAY or not recent_expression_texts.has("今天也摸摸头。"):
		_fail("CompanionMemory did not expose recent expression text: %s" % JSON.stringify(memory_context))
		return
	var corrupt_memory_file = FileAccess.open(config_dir.path_join("companion_memory.json"), FileAccess.WRITE)
	if corrupt_memory_file == null:
		_fail("CompanionMemory file could not be opened for corruption test.")
		return
	corrupt_memory_file.store_string("{broken")
	corrupt_memory_file = null
	memory_store.configure(config_dir, event_store)
	memory_store.refresh(FIXED_ENTERTAINMENT_TIME + 50)
	var recovered_memory = memory_store.snapshot()
	var recovered_counts = recovered_memory.get("short_term", {}).get("counts", {})
	if int(recovered_counts.get("pet_head", 0)) != 1 or int(recovered_counts.get("feed_success", 0)) != 1:
		_fail("CompanionMemory did not recover after invalid JSON: %s" % JSON.stringify(recovered_memory))
		return

	var expression_bank = CompanionExpressionBankScript.new()
	root_node.add_child(expression_bank)
	var pet_expression = expression_bank.resolve("pet_head")
	if not bool(pet_expression.get("found", false)) or str(pet_expression.get("text", "")) != "摸摸头。":
		_fail("CompanionExpressionBank did not return the default pet_head line: %s" % JSON.stringify(pet_expression))
		return
	var repeated_pet_expression = expression_bank.resolve("pet_head")
	if str(repeated_pet_expression.get("text", "")) == str(pet_expression.get("text", "")):
		_fail("CompanionExpressionBank did not avoid a recently used line: %s then %s" % [JSON.stringify(pet_expression), JSON.stringify(repeated_pet_expression)])
		return
	var fallback_expression = expression_bank.resolve("missing_key", {}, "fallback")
	if bool(fallback_expression.get("found", true)) or str(fallback_expression.get("text", "")) != "fallback":
		_fail("CompanionExpressionBank missing key fallback failed: %s" % JSON.stringify(fallback_expression))
		return
	var mode_expression = expression_bank.resolve("mode_changed", {"mode": "活泼"})
	if str(mode_expression.get("text", "")) != "活泼模式。":
		_fail("CompanionExpressionBank template replacement failed: %s" % JSON.stringify(mode_expression))
		return
	var hungry_expression = expression_bank.resolve("auto_prompt:hungry")
	var play_expression = expression_bank.resolve("auto_prompt:play")
	if not bool(hungry_expression.get("found", false)) or not bool(play_expression.get("found", false)):
		_fail("CompanionExpressionBank auto prompt expressions are missing: hungry=%s play=%s" % [JSON.stringify(hungry_expression), JSON.stringify(play_expression)])
		return
	expression_bank.reset_history()
	var contextual_pet_expression = expression_bank.resolve("pet_head", {
		"tone": "short_cute",
		"relationship_level": "familiar",
		"favorite_interactions": ["pet_head"],
		"recent_expression_texts": ["摸摸头。", "再摸一下也可以。"],
	})
	if str(contextual_pet_expression.get("text", "")) != "今天也摸摸头。":
		_fail("CompanionExpressionBank did not select the contextual pet_head line: %s" % JSON.stringify(contextual_pet_expression))
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
	var behavior_config = _load_json("res://assets/behavior.json")
	var active_actions = behavior_config.get("modes", {}).get("活泼", {}).get("actions", [])
	for action in active_actions:
		if typeof(action) == TYPE_DICTIONARY and str(action.get("type", "")) == "mischief":
			_fail("Active mode must not contain mischief actions: %s" % JSON.stringify(action))
			return
	brain.configure(behavior_config)
	brain.set_mode("活泼")
	var decision = brain.decide({
		"busy": false,
		"state": state_store.snapshot(),
		"state_store": state_store,
	}, FIXED_ENTERTAINMENT_TIME)
	if str(decision.get("type", "")) != "prompt" or str(decision.get("name", "")) != "hungry":
		_fail("BehaviorBrain did not produce the expected hungry prompt: %s" % JSON.stringify(decision))
		return
	var hungry_intent = decision.get("intent", {})
	if typeof(hungry_intent) != TYPE_DICTIONARY or str(hungry_intent.get("type", "")) != "care_request" or str(hungry_intent.get("name", "")) != "hungry" or str(hungry_intent.get("reason", "")) == "":
		_fail("BehaviorBrain hungry prompt did not include the expected intent: %s" % JSON.stringify(decision))
		return

	var adaptive_brain = BehaviorBrainScript.new()
	root_node.add_child(adaptive_brain)
	await process_frame
	adaptive_brain.configure({
		"modes": {
			"活泼": {
				"interval": [1.0, 1.0],
				"actions": [{"type": "action", "name": "invite", "weight": 1.0}],
			},
		},
	})
	adaptive_brain.set_mode("活泼")
	var adaptive_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	adaptive_state["memory"]["last_action_at"] = FIXED_ENTERTAINMENT_TIME - 80
	var adaptive_context = {
		"busy": false,
		"state": adaptive_state,
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}
	var adaptive_decision = adaptive_brain.decide(adaptive_context, FIXED_ENTERTAINMENT_TIME)
	if str(adaptive_decision.get("type", "")) != "action" or str(adaptive_decision.get("name", "")) != "invite":
		_fail("BehaviorBrain adaptation did not shorten active cooldown enough for invite: %s" % JSON.stringify(adaptive_decision))
		return
	var adaptation_meta = adaptive_decision.get("adaptation", {})
	var adaptive_intent = adaptive_decision.get("intent", {})
	if typeof(adaptation_meta) != TYPE_DICTIONARY or not bool(adaptation_meta.get("enabled", false)) or float(adaptation_meta.get("cooldown_multiplier", 1.0)) >= 1.0:
		_fail("BehaviorBrain adaptation metadata was missing or ineffective: %s" % JSON.stringify(adaptive_decision))
		return
	if typeof(adaptive_intent) != TYPE_DICTIONARY or str(adaptive_intent.get("reason", "")).find("adaptation") < 0:
		_fail("BehaviorBrain adaptive invite intent did not explain adaptation: %s" % JSON.stringify(adaptive_decision))
		return
	var work_state = _calm_state(FIXED_WORK_TIME)
	work_state["memory"]["last_action_at"] = FIXED_WORK_TIME - 80
	var work_decision = adaptive_brain.decide({
		"busy": false,
		"state": work_state,
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, FIXED_WORK_TIME)
	if str(work_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation bypassed work cooldown: %s" % JSON.stringify(work_decision))
		return

	var threshold_brain = BehaviorBrainScript.new()
	root_node.add_child(threshold_brain)
	await process_frame
	threshold_brain.configure({
		"modes": {
			"活泼": {
				"interval": [1.0, 1.0],
				"actions": [],
			},
		},
	})
	threshold_brain.set_mode("活泼")
	var plain_hungry_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	plain_hungry_state["hunger"] = 76
	var plain_hungry_decision = threshold_brain.decide({"busy": false, "state": plain_hungry_state}, FIXED_ENTERTAINMENT_TIME)
	if str(plain_hungry_decision.get("type", "")) == "prompt" and str(plain_hungry_decision.get("name", "")) == "hungry":
		_fail("BehaviorBrain plain hunger threshold should not trigger at 76: %s" % JSON.stringify(plain_hungry_decision))
		return
	var adapted_hungry_decision = threshold_brain.decide({
		"busy": false,
		"state": plain_hungry_state,
		"memory": _adaptive_memory(["feed_success"], 85, 80, 10),
		"personality": _adaptive_personality(70, 20, 25, 60),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(adapted_hungry_decision.get("type", "")) != "prompt" or str(adapted_hungry_decision.get("name", "")) != "hungry":
		_fail("BehaviorBrain adaptive hunger threshold did not trigger at 76: %s" % JSON.stringify(adapted_hungry_decision))
		return
	var adapted_hungry_intent = adapted_hungry_decision.get("intent", {})
	if typeof(adapted_hungry_intent) != TYPE_DICTIONARY or str(adapted_hungry_intent.get("reason", "")).find("adaptation") < 0:
		_fail("BehaviorBrain adaptive hunger intent did not explain adaptation: %s" % JSON.stringify(adapted_hungry_decision))
		return

	var plain_mood_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	plain_mood_state["mood"] = 45
	var plain_mood_decision = threshold_brain.decide({"busy": false, "state": plain_mood_state}, FIXED_ENTERTAINMENT_TIME)
	if str(plain_mood_decision.get("type", "")) == "prompt" and str(plain_mood_decision.get("name", "")) == "play":
		_fail("BehaviorBrain plain mood threshold should not trigger at 45: %s" % JSON.stringify(plain_mood_decision))
		return
	var adapted_mood_decision = threshold_brain.decide({
		"busy": false,
		"state": plain_mood_state,
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(adapted_mood_decision.get("type", "")) != "prompt" or str(adapted_mood_decision.get("name", "")) != "play":
		_fail("BehaviorBrain adaptive mood threshold did not trigger at 45: %s" % JSON.stringify(adapted_mood_decision))
		return

	adaptive_brain.set_mode("安静")
	var quiet_decision = adaptive_brain.decide({
		"busy": false,
		"state": _calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 80, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(quiet_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not add quiet mode actions: %s" % JSON.stringify(quiet_decision))
		return
	adaptive_brain.set_mode("活泼")
	var busy_decision = adaptive_brain.decide({
		"busy": true,
		"state": _calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(busy_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not bypass busy state: %s" % JSON.stringify(busy_decision))
		return
	adaptive_brain.set_paused(true)
	var paused_decision = adaptive_brain.decide({
		"busy": false,
		"state": _calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(paused_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not bypass paused state: %s" % JSON.stringify(paused_decision))
		return
	adaptive_brain.set_paused(false)
	var rest_decision = adaptive_brain.decide({
		"busy": false,
		"state": _calm_state(FIXED_REST_TIME),
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, FIXED_REST_TIME)
	if str(rest_decision.get("type", "")) != "action" or str(rest_decision.get("name", "")) != "sleep":
		_fail("BehaviorBrain adaptation should preserve rest behavior: %s" % JSON.stringify(rest_decision))
		return

	var effect_brain = BehaviorBrainScript.new()
	root_node.add_child(effect_brain)
	await process_frame
	effect_brain.configure({
		"modes": {
			"活泼": {
				"interval": [1.0, 1.0],
				"actions": [{"type": "effect", "name": "footprint", "weight": 1.0}],
			},
		},
	})
	effect_brain.set_mode("活泼")
	var effect_events := {"effect": "", "mischief": ""}
	effect_brain.effect_requested.connect(func(kind): effect_events["effect"] = str(kind))
	effect_brain.mischief_requested.connect(func(kind): effect_events["mischief"] = str(kind))
	var calm_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	var effect_decision = effect_brain.decide({"busy": false, "state": calm_state}, FIXED_ENTERTAINMENT_TIME)
	if str(effect_decision.get("type", "")) != "effect" or str(effect_decision.get("name", "")) != "footprint":
		_fail("BehaviorBrain did not produce active footprint as an effect: %s" % JSON.stringify(effect_decision))
		return
	effect_brain._emit_decision(effect_decision, {"state": calm_state, "event_store": event_store, "memory_store": memory_store})
	if str(effect_events["effect"]) != "footprint" or str(effect_events["mischief"]) != "":
		_fail("BehaviorBrain effect signal routing was wrong: %s" % JSON.stringify(effect_events))
		return
	var auto_effect_events = event_store.recent_events(1)
	if auto_effect_events.size() != 1 or str(auto_effect_events[0].get("kind", "")) != "auto_effect":
		_fail("BehaviorBrain did not record an auto_effect event: %s" % JSON.stringify(auto_effect_events))
		return
	var auto_memory_counts = memory_store.snapshot().get("short_term", {}).get("counts", {})
	if int(auto_memory_counts.get("auto_effect", 0)) < 1:
		_fail("BehaviorBrain did not refresh CompanionMemory after auto_effect: %s" % JSON.stringify(memory_store.snapshot()))
		return

	var forced_brain = BehaviorBrainScript.new()
	root_node.add_child(forced_brain)
	await process_frame
	forced_brain.configure(behavior_config)
	forced_brain.set_mode("捣乱")
	var forced_now = FIXED_ENTERTAINMENT_TIME + 3600
	var recent_state = _calm_state(forced_now)
	recent_state["memory"]["last_interaction_at"] = forced_now
	forced_brain.request_forced_mischief("grab", 0.0, 6.0, forced_now)
	var busy_forced = forced_brain.decide({"busy": true, "state": recent_state}, forced_now)
	if str(busy_forced.get("type", "")) != "none":
		_fail("Forced mischief must respect busy state: %s" % JSON.stringify(busy_forced))
		return
	forced_brain.set_paused(true)
	var paused_forced = forced_brain.decide({"busy": false, "state": recent_state}, forced_now + 1)
	if str(paused_forced.get("type", "")) != "none":
		_fail("Forced mischief must respect paused state: %s" % JSON.stringify(paused_forced))
		return
	forced_brain.set_paused(false)
	var forced_decision = forced_brain.decide({"busy": false, "state": recent_state}, forced_now + 2)
	if str(forced_decision.get("type", "")) != "mischief" or str(forced_decision.get("name", "")) != "grab":
		_fail("Forced mischief did not bypass recent interaction cooldown: %s" % JSON.stringify(forced_decision))
		return
	var forced_intent = forced_decision.get("intent", {})
	if typeof(forced_intent) != TYPE_DICTIONARY or str(forced_intent.get("type", "")) != "mischief" or str(forced_intent.get("source", "")) != "forced":
		_fail("Forced mischief did not include forced intent metadata: %s" % JSON.stringify(forced_decision))
		return

	var skin_manager = SkinManagerScript.new()
	root_node.add_child(skin_manager)
	skin_manager.configure(repo_root, config_dir, _load_json("res://assets/actions.json"))
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


func _calm_state(now_unix: int) -> Dictionary:
	return {
		"version": 2,
		"mood": 70,
		"hunger": 60,
		"energy": 80,
		"affection": 30,
		"last_decay_at": now_unix,
		"memory": {
			"last_interaction_at": 0,
			"last_interaction_kind": "",
			"last_feed_at": 0,
			"last_play_at": 0,
			"last_prompt_at": 0,
			"last_action_at": 0,
			"interaction_counts": {},
		},
	}


func _adaptive_memory(favorites: Array, familiarity: int, care_score: int, play_score: int) -> Dictionary:
	return {
		"version": 1,
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": "活泼",
			"favorite_period": "entertainment",
		},
		"relationship": {
			"level": "close" if familiarity >= 70 else "familiar",
			"familiarity": familiarity,
			"care_score": care_score,
			"play_score": play_score,
		},
		"short_term": {
			"counts": {},
			"recent_kinds": favorites,
		},
	}


func _adaptive_personality(playfulness: int, mischief: int, patience: int, clinginess: int) -> Dictionary:
	return {
		"version": 1,
		"archetype": "playful",
		"tone": "short_cute",
		"traits": {
			"playfulness": playfulness,
			"mischief": mischief,
			"patience": patience,
			"clinginess": clinginess,
		},
		"dialogue_style": {
			"max_chars": 28,
			"use_status_numbers": false,
			"avoid_repeating_recent": true,
		},
	}


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
