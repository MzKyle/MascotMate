extends SceneTree

const CompanionEventStoreScript = preload("res://scripts/CompanionEventStore.gd")
const CompanionMemoryScript = preload("res://scripts/CompanionMemory.gd")
const CompanionLongTermProfileScript = preload("res://scripts/CompanionLongTermProfile.gd")
const CompanionExpressionBankScript = preload("res://scripts/CompanionExpressionBank.gd")
const CompanionAIExpressionClientScript = preload("res://scripts/CompanionAIExpressionClient.gd")
const CompanionIntentScript = preload("res://scripts/CompanionIntent.gd")
const CompanionExpressionResolverScript = preload("res://scripts/CompanionExpressionResolver.gd")
const TestSupport = preload("res://tests/TestSupport.gd")

const FIXED_ENTERTAINMENT_TIME := 1761998400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var config_dir = TestSupport.config_dir()
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for companion tests.")
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
	var disabled_ai = await ai_client.resolve_expression("pet_head", {"personality": TestSupport.adaptive_personality(70, 20, 60, 40)}, local_expression, "摸摸头，辛苦啦。", 1.8)
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
	}, disabled_ai, {"personality": TestSupport.adaptive_personality(70, 20, 60, 40)})
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
	}, disabled_ai, {"personality": TestSupport.adaptive_personality(70, 20, 60, 40)})
	if str(long_ai.get("source", "")) == "ai" or str(long_ai.get("fallback_reason", "")) != "too_long":
		_fail("CompanionAIExpressionClient did not reject overlong AI text: %s" % JSON.stringify(long_ai))
		return
	ai_client.configure({"enabled": true, "provider": "local_stub", "timeout_ms": 800})
	var cache_context = {
		"intent": CompanionIntentScript.social_response("pet_head"),
		"state": {"mood": 70, "hunger": 60, "energy": 80, "affection": 30},
		"personality": TestSupport.adaptive_personality(70, 20, 60, 40),
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


	print("Godot companion test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
