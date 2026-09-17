extends SceneTree

const StateStoreScript = preload("res://scripts/StateStore.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const CompanionBehaviorPolicyScript = preload("res://scripts/CompanionBehaviorPolicy.gd")
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
const CompanionExpressionBankScript = preload("res://scripts/CompanionExpressionBank.gd")
const CompanionAIExpressionClientScript = preload("res://scripts/CompanionAIExpressionClient.gd")
const CompanionIntentScript = preload("res://scripts/CompanionIntent.gd")
const CompanionExpressionResolverScript = preload("res://scripts/CompanionExpressionResolver.gd")
const MischiefControllerScript = preload("res://scripts/MischiefController.gd")

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

	var window_controller = PetWindowControllerScript.new()
	root_node.add_child(window_controller)
	await process_frame
	window_controller.configure(root_node, root_node)
	if window_controller.is_transparent() or window_controller.is_mouse_passthrough_enabled():
		_fail("PetWindowController should honor safe smoke window flags: %s" % JSON.stringify(window_controller.debug_state()))
		return
	var window_state = window_controller.debug_state()
	for key in ["transparent_window", "mouse_passthrough_enabled", "borderless", "always_on_top", "window_transparent", "viewport_transparent_bg", "position", "size"]:
		if not window_state.has(key):
			_fail("PetWindowController debug_state missing key %s: %s" % [key, JSON.stringify(window_state)])
			return
	var original_window_position = window_controller.position()
	var rounded_target = Vector2i(round(float(original_window_position.x) + 12.4), round(float(original_window_position.y) + 7.6))
	window_controller.apply_position(Vector2(float(original_window_position.x) + 12.4, float(original_window_position.y) + 7.6))
	if window_controller.position() != rounded_target:
		_fail("PetWindowController did not round/apply position: expected=%s actual=%s" % [str(rounded_target), str(window_controller.position())])
		return
	window_controller.apply_position(Vector2(float(rounded_target.x), float(rounded_target.y)))
	if window_controller.position() != rounded_target:
		_fail("PetWindowController changed position after applying same value: %s" % str(window_controller.position()))
		return
	window_controller.transparent_window = true
	window_controller.mouse_passthrough_enabled = true
	var polygon_a = PackedVector2Array([Vector2.ZERO, Vector2(24, 0), Vector2(24, 24), Vector2(0, 24)])
	var polygon_b = PackedVector2Array([Vector2.ZERO, Vector2(32, 0), Vector2(32, 32), Vector2(0, 32)])
	window_controller.set_mouse_passthrough_polygon(polygon_a)
	window_controller.set_mouse_passthrough_polygon(polygon_a)
	if window_controller.mouse_passthrough_polygon().size() != polygon_a.size() or window_controller.mouse_passthrough_polygon()[1] != polygon_a[1]:
		_fail("PetWindowController passthrough cache did not retain same polygon: %s" % str(window_controller.mouse_passthrough_polygon()))
		return
	window_controller.set_mouse_passthrough_polygon(polygon_b)
	if window_controller.mouse_passthrough_polygon().size() != polygon_b.size() or window_controller.mouse_passthrough_polygon()[1] != polygon_b[1]:
		_fail("PetWindowController passthrough cache did not update changed polygon: %s" % str(window_controller.mouse_passthrough_polygon()))
		return
	window_controller.transparent_window = false
	window_controller.mouse_passthrough_enabled = false
	window_controller.set_mouse_passthrough_polygon(polygon_b)
	if window_controller.mouse_passthrough_polygon().size() != 0:
		_fail("PetWindowController did not clear passthrough when disabled: %s" % str(window_controller.mouse_passthrough_polygon()))
		return
	window_controller.apply_position(Vector2(float(original_window_position.x), float(original_window_position.y)))

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
	memory_store.record_expression("pet_head", "今天也很棒。", FIXED_ENTERTAINMENT_TIME + 41)
	var memory_context = memory_store.expression_context({"mode": "活泼"})
	var recent_expression_texts = memory_context.get("recent_expression_texts", [])
	if typeof(recent_expression_texts) != TYPE_ARRAY or not recent_expression_texts.has("今天也很棒。"):
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

	var profile_store = CompanionLongTermProfileScript.new()
	root_node.add_child(profile_store)
	profile_store.configure(config_dir, event_store, memory_store)
	profile_store.refresh(FIXED_ENTERTAINMENT_TIME + 60)
	var profile_snapshot = profile_store.snapshot()
	var lifetime_counts = profile_snapshot.get("lifetime", {}).get("counts", {})
	var profile_preferences = profile_snapshot.get("preferences", {})
	if int(lifetime_counts.get("pet_head", 0)) != 1 or int(lifetime_counts.get("feed_success", 0)) != 1 or int(lifetime_counts.get("tease_success", 0)) != 1:
		_fail("CompanionLongTermProfile did not aggregate lifetime counts: %s" % JSON.stringify(profile_snapshot))
		return
	var profile_favorites = profile_preferences.get("favorite_interactions", [])
	if typeof(profile_favorites) != TYPE_ARRAY or not profile_favorites.has("feed_success") or str(profile_preferences.get("interruption_tolerance", "")) == "":
		_fail("CompanionLongTermProfile did not derive preferences: %s" % JSON.stringify(profile_snapshot))
		return
	var profile_context = profile_store.expression_context({"mode": "活泼"})
	if typeof(profile_context.get("profile", {})) != TYPE_DICTIONARY or str(profile_context.get("mode", "")) != "活泼":
		_fail("CompanionLongTermProfile expression context failed: %s" % JSON.stringify(profile_context))
		return
	var low_confidence_applied = profile_store.apply_ai_summary({
		"favorite_interactions": ["feed_success"],
		"care_tendency": 95,
		"play_tendency": 5,
		"interruption_tolerance": "low",
		"confidence": 40,
	}, FIXED_ENTERTAINMENT_TIME + 61)
	if low_confidence_applied:
		_fail("CompanionLongTermProfile accepted a low-confidence AI summary.")
		return
	var high_confidence_applied = profile_store.apply_ai_summary({
		"favorite_interactions": ["feed_success"],
		"favorite_mode": "活泼",
		"favorite_period": "entertainment",
		"care_tendency": 100,
		"play_tendency": 0,
		"interruption_tolerance": "high",
		"confidence": 85,
	}, FIXED_ENTERTAINMENT_TIME + 62)
	var effective_preferences = profile_store.snapshot().get("effective_preferences", {})
	if not high_confidence_applied or int(effective_preferences.get("care_tendency", 0)) > int(profile_preferences.get("care_tendency", 0)) + 10:
		_fail("CompanionLongTermProfile did not softly merge AI summary: %s" % JSON.stringify(profile_store.snapshot()))
		return
	var corrupt_profile_file = FileAccess.open(config_dir.path_join("companion_profile.json"), FileAccess.WRITE)
	if corrupt_profile_file == null:
		_fail("CompanionLongTermProfile file could not be opened for corruption test.")
		return
	corrupt_profile_file.store_string("{broken")
	corrupt_profile_file = null
	profile_store.configure(config_dir, event_store, memory_store)
	profile_store.refresh(FIXED_ENTERTAINMENT_TIME + 70)
	var recovered_profile_counts = profile_store.snapshot().get("lifetime", {}).get("counts", {})
	if int(recovered_profile_counts.get("pet_head", 0)) != 1:
		_fail("CompanionLongTermProfile did not recover after invalid JSON: %s" % JSON.stringify(profile_store.snapshot()))
		return

	var ai_client = CompanionAIExpressionClientScript.new()
	root_node.add_child(ai_client)
	ai_client.configure({"enabled": false, "provider": "local_stub", "timeout_ms": 800})
	var local_expression = {"found": true, "text": "摸摸头，辛苦啦。", "seconds": 1.8}
	var disabled_ai = await ai_client.resolve_expression("pet_head", {"personality": _adaptive_personality(70, 20, 60, 40)}, local_expression, "摸摸头，辛苦啦。", 1.8)
	if str(disabled_ai.get("source", "")) != "local" or str(disabled_ai.get("text", "")) != "摸摸头，辛苦啦。":
		_fail("CompanionAIExpressionClient disabled path should use local expression: %s" % JSON.stringify(disabled_ai))
		return
	var disabled_ai_status = ai_client.status()
	if typeof(disabled_ai_status.get("recent_results", [])) != TYPE_ARRAY or disabled_ai_status.get("recent_results", []).size() != 1 or int(disabled_ai_status.get("source_stats", {}).get("local", 0)) != 1:
		_fail("CompanionAIExpressionClient did not record local expression diagnostics: %s" % JSON.stringify(disabled_ai_status))
		return
	var disabled_health = await ai_client.check_health()
	if str(disabled_health.get("status", "")) != "disabled":
		_fail("CompanionAIExpressionClient disabled health should be explicit: %s" % JSON.stringify(disabled_health))
		return
	var valid_ai = ai_client._validate_response({
		"text": "AI说辛苦啦。",
		"seconds": 1.2,
		"emotion": "happy",
		"safety": "ok",
	}, disabled_ai, {"personality": _adaptive_personality(70, 20, 60, 40)})
	if str(valid_ai.get("source", "")) != "ai" or str(valid_ai.get("text", "")) != "AI说辛苦啦。":
		_fail("CompanionAIExpressionClient did not accept a valid AI response: %s" % JSON.stringify(valid_ai))
		return
	var invalid_ai = ai_client._validate_response({
		"text": "bad",
		"seconds": 1.0,
		"emotion": "neutral",
		"safety": "ok",
		"command": "walk",
	}, disabled_ai, {})
	if str(invalid_ai.get("source", "")) == "ai" or str(invalid_ai.get("fallback_reason", "")) != "unknown_field":
		_fail("CompanionAIExpressionClient did not reject unknown AI fields: %s" % JSON.stringify(invalid_ai))
		return
	var long_ai = ai_client._validate_response({
		"text": "这是一句非常非常非常非常非常非常非常非常非常长的气泡文案。",
		"seconds": 1.0,
		"emotion": "neutral",
		"safety": "ok",
	}, disabled_ai, {"personality": _adaptive_personality(70, 20, 60, 40)})
	if str(long_ai.get("source", "")) == "ai" or str(long_ai.get("fallback_reason", "")) != "too_long":
		_fail("CompanionAIExpressionClient did not reject overlong AI text: %s" % JSON.stringify(long_ai))
		return
	ai_client.configure({"enabled": true, "provider": "local_stub", "timeout_ms": 800})
	var cache_context = {
		"intent": CompanionIntentScript.social_response("pet_head"),
		"state": {"mood": 70, "hunger": 60, "energy": 80, "affection": 30},
		"personality": _adaptive_personality(70, 20, 60, 40),
		"recent_expression_texts": [],
	}
	var cache_key = ai_client._cache_key("pet_head", cache_context, ai_client._local_result(local_expression, "摸摸头，辛苦啦。", 1.8, "local"))
	ai_client._store_cache(cache_key, {
		"text": "缓存摸摸头。",
		"seconds": 1.0,
		"source": "ai",
		"emotion": "happy",
		"fallback_reason": "",
		"cache_hit": false,
	})
	var cached_ai = await ai_client.resolve_expression("pet_head", cache_context, local_expression, "摸摸头，辛苦啦。", 1.8)
	if str(cached_ai.get("source", "")) != "ai_cache" or not bool(cached_ai.get("cache_hit", false)):
		_fail("CompanionAIExpressionClient did not serve a cached expression: %s" % JSON.stringify(cached_ai))
		return
	var cached_status = ai_client.status()
	if int(cached_status.get("source_stats", {}).get("ai_cache", 0)) != 1:
		_fail("CompanionAIExpressionClient did not record cache diagnostics: %s" % JSON.stringify(cached_status))
		return
	ai_client.configure({"enabled": true, "provider": "local_stub", "timeout_ms": 900})
	if int(ai_client.status().get("cache", {}).get("size", -1)) != 0:
		_fail("CompanionAIExpressionClient did not clear cache on configure: %s" % JSON.stringify(ai_client.status()))
		return
	ai_client.configure_memory_summary({"enabled": false})
	var disabled_summary = await ai_client.summarize_memory({"recent_events": []}, true)
	if str(disabled_summary.get("fallback_reason", "")) != "disabled":
		_fail("CompanionAIExpressionClient disabled memory summary should not request sidecar: %s" % JSON.stringify(disabled_summary))
		return
	var low_summary = ai_client._validate_memory_summary({
		"favorite_interactions": ["feed_success"],
		"favorite_mode": "活泼",
		"favorite_period": "entertainment",
		"care_tendency": 90,
		"play_tendency": 10,
		"interruption_tolerance": "medium",
		"confidence": 40,
		"safety": "ok",
	})
	if str(low_summary.get("fallback_reason", "")) != "low_confidence":
		_fail("CompanionAIExpressionClient did not reject low-confidence memory summary: %s" % JSON.stringify(low_summary))
		return

	var expression_bank = CompanionExpressionBankScript.new()
	root_node.add_child(expression_bank)
	var pet_expression = expression_bank.resolve("pet_head")
	if not bool(pet_expression.get("found", false)) or str(pet_expression.get("text", "")) != "摸摸头，辛苦啦。":
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
	if str(mode_expression.get("text", "")) != "已切到活泼模式，我会配合你。":
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
		"recent_expression_texts": ["今天也很棒。", "摸摸头，辛苦啦。"],
	})
	if str(contextual_pet_expression.get("text", "")) != "你一摸头，我就充满电。":
		_fail("CompanionExpressionBank did not select the contextual pet_head line: %s" % JSON.stringify(contextual_pet_expression))
		return
	var social_intent = CompanionIntentScript.social_response("pet_head")
	if not CompanionIntentScript.is_valid(social_intent) or str(social_intent.get("key", "")) != "social_response:pet_head":
		_fail("CompanionIntent did not construct a valid social response intent: %s" % JSON.stringify(social_intent))
		return
	var expression_resolver = CompanionExpressionResolverScript.new()
	var social_expression = expression_resolver.resolve(social_intent, {"type": "interaction", "name": "pet_head"})
	if str(social_expression.get("bubble", {}).get("key", "")) != "pet_head" or str(social_expression.get("effect", "")) != "heart":
		_fail("CompanionExpressionResolver did not resolve pet_head expression: %s" % JSON.stringify(social_expression))
		return
	var sleep_expression = expression_resolver.resolve(CompanionIntentScript.make("rest_request", "sleepy"), {"type": "action", "name": "sleep"})
	if str(sleep_expression.get("action", "")) != "sleep" or not bool(sleep_expression.get("state_delta", {}).get("sleep_tick", false)):
		_fail("CompanionExpressionResolver did not resolve sleep expression: %s" % JSON.stringify(sleep_expression))
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
	var local_work_time = _unix_for_local_datetime(2025, 11, 3, 11)
	var local_rest_time = _unix_for_local_datetime(2025, 11, 3, 2)
	if str(brain.period_for(local_work_time)) != "work":
		_fail("BehaviorBrain period calculation must use local work time: %s" % str(brain.period_for(local_work_time)))
		return
	if str(brain.period_for(local_rest_time)) != "rest":
		_fail("BehaviorBrain period calculation must use local rest time: %s" % str(brain.period_for(local_rest_time)))
		return
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
	var delegate_brain = BehaviorBrainScript.new()
	root_node.add_child(delegate_brain)
	delegate_brain.configure(behavior_config)
	delegate_brain.set_mode("活泼")
	var delegate_context = {"busy": true, "state": _calm_state(FIXED_ENTERTAINMENT_TIME)}
	var brain_delegate_decision = delegate_brain.decide(delegate_context, FIXED_ENTERTAINMENT_TIME)
	var policy = CompanionBehaviorPolicyScript.new()
	policy.configure(behavior_config)
	policy.set_mode("活泼")
	var policy_delegate_decision = policy.decide(
		delegate_context,
		FIXED_ENTERTAINMENT_TIME,
		{"last_interaction_at": 0, "last_prompt_at": 0, "last_action_at": 0},
		{"kind": "", "ready_at": 0.0, "expires_at": 0.0},
		false
	)
	if str(brain_delegate_decision.get("type", "")) != str(policy_delegate_decision.get("type", "")) or str(brain_delegate_decision.get("reason", "")) != "busy" or str(policy_delegate_decision.get("reason", "")) != "busy":
		_fail("BehaviorBrain did not delegate busy decisions to CompanionBehaviorPolicy: brain=%s policy=%s" % [JSON.stringify(brain_delegate_decision), JSON.stringify(policy_delegate_decision)])
		return
	delegate_brain.free()
	var emitted_intent := {"intent": {}}
	brain.intent_requested.connect(func(intent, _decision): emitted_intent["intent"] = intent)
	brain._emit_decision(decision, {"busy": false, "state": state_store.snapshot(), "state_store": state_store})
	if str(emitted_intent.get("intent", {}).get("key", "")) != "care_request:hungry":
		_fail("BehaviorBrain did not emit intent_requested for automatic prompt: %s" % JSON.stringify(emitted_intent))
		return

	var main_probe = MainScript.new()
	main_probe.physics = PetPhysicsScript.new()
	main_probe.mini_games = MiniGamesScript.new()
	if main_probe._busy():
		_fail("Main probe should not start busy.")
		return
	main_probe._lock_auto_behavior(1.0)
	if not main_probe._busy():
		_fail("Main auto behavior lock did not mark runtime busy.")
		return
	main_probe._clear_auto_behavior_lock()
	if main_probe._busy():
		_fail("Main auto behavior lock did not clear.")
		return
	main_probe.physics.free()
	main_probe.mini_games.free()
	main_probe.free()

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
	var work_state = _calm_state(local_work_time)
	work_state["memory"]["last_action_at"] = local_work_time - 80
	var work_decision = adaptive_brain.decide({
		"busy": false,
		"state": work_state,
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, local_work_time)
	if str(work_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation bypassed work cooldown: %s" % JSON.stringify(work_decision))
		return

	var low_interrupt_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	low_interrupt_state["memory"]["last_action_at"] = FIXED_ENTERTAINMENT_TIME - 130
	var low_interrupt_decision = adaptive_brain.decide({
		"busy": false,
		"state": low_interrupt_state,
		"memory": _adaptive_memory([], 20, 0, 0),
		"profile": _adaptive_profile(10, 10, "low", "安静", "entertainment"),
		"personality": _adaptive_personality(45, 20, 85, 20),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(low_interrupt_decision.get("type", "")) != "none" or str(low_interrupt_decision.get("reason", "")) != "attention_cooldown" or float(low_interrupt_decision.get("adaptation", {}).get("cooldown_multiplier", 1.0)) <= 1.0 or not _decision_has_profile_reason(low_interrupt_decision):
		_fail("BehaviorBrain low-interruption profile did not lengthen active cooldown: %s" % JSON.stringify(low_interrupt_decision))
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
	var profile_hungry_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	profile_hungry_state["hunger"] = 78
	var profile_hungry_decision = threshold_brain.decide({
		"busy": false,
		"state": profile_hungry_state,
		"memory": _adaptive_memory([], 25, 0, 0),
		"profile": _adaptive_profile(90, 10, "medium", "活泼", "entertainment", ["feed_success"]),
		"personality": _adaptive_personality(50, 20, 50, 40),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(profile_hungry_decision.get("type", "")) != "prompt" or str(profile_hungry_decision.get("name", "")) != "hungry" or not _decision_has_profile_reason(profile_hungry_decision) or int(profile_hungry_decision.get("adaptation", {}).get("hunger_threshold", 80)) >= 80:
		_fail("BehaviorBrain profile care tendency did not lower hunger threshold: %s" % JSON.stringify(profile_hungry_decision))
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
	var profile_mood_state = _calm_state(FIXED_ENTERTAINMENT_TIME)
	profile_mood_state["mood"] = 38
	var profile_mood_decision = threshold_brain.decide({
		"busy": false,
		"state": profile_mood_state,
		"memory": _adaptive_memory([], 25, 0, 0),
		"profile": _adaptive_profile(10, 90, "high", "活泼", "entertainment", ["tease_success"]),
		"personality": _adaptive_personality(50, 20, 50, 40),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(profile_mood_decision.get("type", "")) != "prompt" or str(profile_mood_decision.get("name", "")) != "play" or not _decision_has_profile_reason(profile_mood_decision) or int(profile_mood_decision.get("adaptation", {}).get("play_threshold", 35)) <= 35:
		_fail("BehaviorBrain profile play tendency did not raise play threshold: %s" % JSON.stringify(profile_mood_decision))
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
		"state": _calm_state(local_rest_time),
		"memory": _adaptive_memory(["tease_success"], 85, 10, 80),
		"profile": _adaptive_profile(10, 90, "high", "活泼", "rest", ["tease_success"]),
		"personality": _adaptive_personality(95, 25, 20, 90),
	}, local_rest_time)
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
	for tone in ["gentle", "short_cute", "calm"]:
		if config_store.normalize_dialogue_tone(tone) != tone:
			_fail("ConfigStore rejected valid dialogue tone: %s" % tone)
			return
	if config_store.normalize_dialogue_tone("loud") != "gentle":
		_fail("ConfigStore did not fallback invalid dialogue tone.")
		return
	var normalized_adaptation = config_store.normalize_behavior_adaptation({"enabled": false, "strength": "loud"})
	if bool(normalized_adaptation.get("enabled", true)) or str(normalized_adaptation.get("strength", "")) != "visible":
		_fail("ConfigStore did not normalize behavior adaptation fallback: %s" % JSON.stringify(normalized_adaptation))
		return
	normalized_adaptation = config_store.normalize_behavior_adaptation({"enabled": true, "strength": "bold"})
	if not bool(normalized_adaptation.get("enabled", false)) or str(normalized_adaptation.get("strength", "")) != "bold":
		_fail("ConfigStore did not preserve valid behavior adaptation: %s" % JSON.stringify(normalized_adaptation))
		return
	var ai_before_normalize = config_store.app_config().get("ai_expression", {})
	var normalized_ai = config_store.normalize_ai_expression({"enabled": true, "provider": "openai_compatible", "timeout_ms": 1200})
	if not bool(normalized_ai.get("enabled", false)) or str(normalized_ai.get("provider", "")) != "openai_compatible" or int(normalized_ai.get("timeout_ms", 0)) != 1200:
		_fail("ConfigStore did not preserve valid AI expression config: %s" % JSON.stringify(normalized_ai))
		return
	var ai_after_normalize = config_store.app_config().get("ai_expression", {})
	if bool(ai_after_normalize.get("enabled", false)) != bool(ai_before_normalize.get("enabled", false)) or int(ai_after_normalize.get("timeout_ms", 0)) != int(ai_before_normalize.get("timeout_ms", 0)):
		_fail("ConfigStore normalize_ai_expression unexpectedly persisted config: before=%s after=%s" % [JSON.stringify(ai_before_normalize), JSON.stringify(ai_after_normalize)])
		return
	normalized_ai = config_store.normalize_ai_expression({"provider": "bad", "timeout_ms": 1})
	if str(normalized_ai.get("provider", "")) != "local_stub" or int(normalized_ai.get("timeout_ms", 0)) != 100:
		_fail("ConfigStore did not clamp/fallback low AI expression config: %s" % JSON.stringify(normalized_ai))
		return
	normalized_ai = config_store.normalize_ai_expression({"timeout_ms": 999999})
	if int(normalized_ai.get("timeout_ms", 0)) != 5000:
		_fail("ConfigStore did not clamp high AI expression timeout: %s" % JSON.stringify(normalized_ai))
		return
	var normalized_summary = config_store.normalize_ai_memory_summary({
		"enabled": true,
		"provider": "openai_compatible",
		"timeout_ms": 1600,
		"min_events": 20,
		"min_interval_seconds": 900,
	})
	if not bool(normalized_summary.get("enabled", false)) or str(normalized_summary.get("provider", "")) != "openai_compatible" or int(normalized_summary.get("timeout_ms", 0)) != 1600 or int(normalized_summary.get("min_events", 0)) != 20 or int(normalized_summary.get("min_interval_seconds", 0)) != 900:
		_fail("ConfigStore did not preserve valid AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	normalized_summary = config_store.normalize_ai_memory_summary({
		"provider": "bad",
		"timeout_ms": 1,
		"min_events": 0,
		"min_interval_seconds": 1,
	})
	if str(normalized_summary.get("provider", "")) != "local_stub" or int(normalized_summary.get("timeout_ms", 0)) != 100 or int(normalized_summary.get("min_events", 0)) != 1 or int(normalized_summary.get("min_interval_seconds", 0)) != 60:
		_fail("ConfigStore did not clamp/fallback low AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	normalized_summary = config_store.normalize_ai_memory_summary({
		"timeout_ms": 999999,
		"min_events": 999,
		"min_interval_seconds": 999999999,
	})
	if int(normalized_summary.get("timeout_ms", 0)) != 5000 or int(normalized_summary.get("min_events", 0)) != 200 or int(normalized_summary.get("min_interval_seconds", 0)) != 30 * 24 * 60 * 60:
		_fail("ConfigStore did not clamp high AI memory summary config: %s" % JSON.stringify(normalized_summary))
		return
	config_store.set_behavior_adaptation_config({"enabled": false, "strength": "bold"})
	var adaptation_config = config_store.app_config().get("behavior_adaptation", {})
	if bool(adaptation_config.get("enabled", true)) or str(adaptation_config.get("strength", "")) != "bold":
		_fail("ConfigStore did not persist behavior adaptation config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_dialogue_tone("calm")
	if str(config_store.app_config().get("dialogue_tone", "")) != "calm":
		_fail("ConfigStore did not persist dialogue tone config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_ai_expression_config({"enabled": true, "provider": "local_stub", "timeout_ms": 1200})
	var ai_config = config_store.app_config().get("ai_expression", {})
	if not bool(ai_config.get("enabled", false)) or str(ai_config.get("provider", "")) != "local_stub" or int(ai_config.get("timeout_ms", 0)) != 1200:
		_fail("ConfigStore did not persist AI expression config: %s" % JSON.stringify(config_store.get_config()))
		return
	config_store.set_ai_memory_summary_config({"enabled": true, "provider": "local_stub", "timeout_ms": 1500, "min_events": 5, "min_interval_seconds": 600})
	var summary_config = config_store.app_config().get("ai_memory_summary", {})
	if not bool(summary_config.get("enabled", false)) or int(summary_config.get("min_events", 0)) != 5 or int(summary_config.get("min_interval_seconds", 0)) != 600:
		_fail("ConfigStore did not persist AI memory summary config: %s" % JSON.stringify(config_store.get_config()))
		return

	var observed_brain = BehaviorBrainScript.new()
	root_node.add_child(observed_brain)
	await process_frame
	observed_brain.configure(behavior_config)
	observed_brain.set_mode("活泼")
	var observed := {"decision": {}}
	observed_brain.decision_observed.connect(func(decision, _context): observed["decision"] = decision)
	observed_brain.set_context_provider(func(): return {"busy": true, "state": _calm_state(FIXED_ENTERTAINMENT_TIME)})
	observed_brain._decide()
	if str(observed["decision"].get("type", "")) != "none" or str(observed["decision"].get("reason", "")) != "busy":
		_fail("BehaviorBrain decision_observed did not expose the busy none decision: %s" % JSON.stringify(observed))
		return

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
	var debug_snapshot = _load_json(main_debug.companion_debug_snapshot_path)
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
	var events_before_scenario = event_store.all_events().size()
	var scenario_result = main_debug._run_companion_scenarios("all")
	if bool(scenario_result.get("mutated_events", true)) or event_store.all_events().size() != events_before_scenario:
		_fail("Main companion scenario replay mutated events: %s" % JSON.stringify(scenario_result))
		return
	var scenarios = scenario_result.get("scenarios", [])
	if typeof(scenarios) != TYPE_ARRAY or scenarios.size() != 11:
		_fail("Main companion scenario replay did not return all scenarios: %s" % JSON.stringify(scenario_result))
		return
	for scenario in scenarios:
		if typeof(scenario) != TYPE_DICTIONARY or not bool(scenario.get("passed", false)):
			_fail("Main companion scenario failed: %s" % JSON.stringify(scenario_result))
			return
	var scenario_file = _load_json(main_debug.companion_scenario_result_path)
	if scenario_file.get("scenarios", []).size() != 11:
		_fail("Main companion scenario result file was not written: %s" % JSON.stringify(scenario_file))
		return
	main_debug.physics.free()
	main_debug.mini_games.free()
	main_debug.brain.free()
	main_debug.free()

	var pet_sprite = PetSpriteScript.new()
	root_node.add_child(pet_sprite)
	await process_frame
	pet_sprite.configure_skin(skin_manager.current_skin, skin_manager.current_frame_root)
	if not pet_sprite.play("idle"):
		_fail("PetSprite could not play idle.")
		return
	var mischief_pet_sprite = PetSpriteScript.new()
	var mischief_physics = PetPhysicsScript.new()
	root_node.add_child(mischief_physics)
	var mischief_probe = MischiefControllerScript.new()
	root_node.add_child(mischief_pet_sprite)
	root_node.add_child(mischief_probe)
	await process_frame
	mischief_pet_sprite.configure_skin(skin_manager.current_skin, skin_manager.current_frame_root)
	var observed_mischief_position := {"count": 0, "position": Vector2(-9999, -9999)}
	mischief_probe.configure(
		mischief_pet_sprite,
		mischief_physics,
		func(): return Rect2(Vector2.ZERO, Vector2(1200, 800)),
		func(pos): observed_mischief_position["count"] = int(observed_mischief_position["count"]) + 1; observed_mischief_position["position"] = pos
	)
	if not mischief_probe.start():
		_fail("MischiefController probe could not start.")
		return
	mischief_probe.tick(0.0, Vector2(220, 180))
	if int(observed_mischief_position.get("count", 0)) != 1 or observed_mischief_position.get("position", Vector2.ZERO) != mischief_physics.position:
		_fail("MischiefController did not submit physics.position through the position sink: observed=%s physics=%s" % [str(observed_mischief_position), str(mischief_physics.position)])
		return
	mischief_probe.stop()
	mischief_probe.free()
	mischief_physics.free()
	mischief_pet_sprite.free()
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


func _adaptive_profile(care_tendency: int, play_tendency: int, interruption_tolerance: String, favorite_mode := "活泼", favorite_period := "entertainment", favorites := []) -> Dictionary:
	return {
		"version": 1,
		"updated_at": 0,
		"lifetime": {
			"total_events": 0,
			"counts": {},
			"mode_counts": {},
			"period_counts": {},
			"care_score": care_tendency,
			"play_score": play_tendency,
			"disruption_score": 0,
			"last_event_at": 0,
			"processed_event_ids": [],
		},
		"trends": {},
		"preferences": {
			"favorite_interactions": favorites,
			"favorite_mode": favorite_mode,
			"favorite_period": favorite_period,
			"care_tendency": care_tendency,
			"play_tendency": play_tendency,
			"interruption_tolerance": interruption_tolerance,
		},
		"relationship": {
			"level": "familiar",
			"familiarity": 45,
			"care_score": care_tendency,
			"play_score": play_tendency,
		},
	}


func _decision_has_profile_reason(decision: Dictionary) -> bool:
	var adaptation = decision.get("adaptation", {})
	if typeof(adaptation) != TYPE_DICTIONARY:
		return false
	var reasons = adaptation.get("reasons", [])
	if typeof(reasons) != TYPE_ARRAY:
		return false
	for reason in reasons:
		if str(reason).find("profile") >= 0:
			return true
	return false


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


func _unix_for_local_datetime(year: int, month: int, day: int, hour: int) -> int:
	var utc_unix = int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": 0,
		"second": 0,
	}))
	var time_zone = Time.get_time_zone_from_system()
	var bias_minutes = int(time_zone.get("bias", 0)) if typeof(time_zone) == TYPE_DICTIONARY else 0
	return utc_unix - bias_minutes * 60


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
