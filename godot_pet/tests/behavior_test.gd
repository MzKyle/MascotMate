extends SceneTree

const StateStoreScript = preload("res://scripts/StateStore.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const CompanionBehaviorPolicyScript = preload("res://scripts/CompanionBehaviorPolicy.gd")
const CompanionScenarioRunnerScript = preload("res://scripts/CompanionScenarioRunner.gd")
const CompanionEventStoreScript = preload("res://scripts/CompanionEventStore.gd")
const CompanionMemoryScript = preload("res://scripts/CompanionMemory.gd")
const ConfigStoreScript = preload("res://scripts/ConfigStore.gd")
const MainScript = preload("res://scripts/Main.gd")
const PetPhysicsScript = preload("res://scripts/PetPhysics.gd")
const MiniGamesScript = preload("res://scripts/MiniGames.gd")
const TestSupport = preload("res://tests/TestSupport.gd")

const FIXED_ENTERTAINMENT_TIME := 1761998400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var config_dir = TestSupport.config_dir()
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for behavior tests.")
		return
	var event_store = CompanionEventStoreScript.new()
	root_node.add_child(event_store)
	event_store.configure(config_dir)
	var memory_store = CompanionMemoryScript.new()
	root_node.add_child(memory_store)
	memory_store.configure(config_dir, event_store)

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
	var behavior_config = TestSupport.load_json("res://assets/behavior.json")
	var active_actions = behavior_config.get("modes", {}).get("活泼", {}).get("actions", [])
	for action in active_actions:
		if typeof(action) == TYPE_DICTIONARY and str(action.get("type", "")) == "mischief":
			_fail("Active mode must not contain mischief actions: %s" % JSON.stringify(action))
			return
	brain.configure(behavior_config)
	brain.set_mode("活泼")
	var local_work_time = TestSupport.unix_for_local_datetime(2025, 11, 3, 11)
	var local_rest_time = TestSupport.unix_for_local_datetime(2025, 11, 3, 2)
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
	var delegate_context = {"busy": true, "state": TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)}
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
	var adaptive_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	adaptive_state["memory"]["last_action_at"] = FIXED_ENTERTAINMENT_TIME - 80
	var adaptive_context = {
		"busy": false,
		"state": adaptive_state,
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
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
	var work_state = TestSupport.calm_state(local_work_time)
	work_state["memory"]["last_action_at"] = local_work_time - 80
	var work_decision = adaptive_brain.decide({
		"busy": false,
		"state": work_state,
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
	}, local_work_time)
	if str(work_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation bypassed work cooldown: %s" % JSON.stringify(work_decision))
		return

	var low_interrupt_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	low_interrupt_state["memory"]["last_action_at"] = FIXED_ENTERTAINMENT_TIME - 130
	var low_interrupt_decision = adaptive_brain.decide({
		"busy": false,
		"state": low_interrupt_state,
		"memory": TestSupport.adaptive_memory([], 20, 0, 0),
		"profile": TestSupport.adaptive_profile(10, 10, "low", "安静", "entertainment"),
		"personality": TestSupport.adaptive_personality(45, 20, 85, 20),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(low_interrupt_decision.get("type", "")) != "none" or str(low_interrupt_decision.get("reason", "")) != "attention_cooldown" or float(low_interrupt_decision.get("adaptation", {}).get("cooldown_multiplier", 1.0)) <= 1.0 or not TestSupport.decision_has_profile_reason(low_interrupt_decision):
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
	var plain_hungry_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	plain_hungry_state["hunger"] = 76
	var plain_hungry_decision = threshold_brain.decide({"busy": false, "state": plain_hungry_state}, FIXED_ENTERTAINMENT_TIME)
	if str(plain_hungry_decision.get("type", "")) == "prompt" and str(plain_hungry_decision.get("name", "")) == "hungry":
		_fail("BehaviorBrain plain hunger threshold should not trigger at 76: %s" % JSON.stringify(plain_hungry_decision))
		return
	var adapted_hungry_decision = threshold_brain.decide({
		"busy": false,
		"state": plain_hungry_state,
		"memory": TestSupport.adaptive_memory(["feed_success"], 85, 80, 10),
		"personality": TestSupport.adaptive_personality(70, 20, 25, 60),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(adapted_hungry_decision.get("type", "")) != "prompt" or str(adapted_hungry_decision.get("name", "")) != "hungry":
		_fail("BehaviorBrain adaptive hunger threshold did not trigger at 76: %s" % JSON.stringify(adapted_hungry_decision))
		return
	var adapted_hungry_intent = adapted_hungry_decision.get("intent", {})
	if typeof(adapted_hungry_intent) != TYPE_DICTIONARY or str(adapted_hungry_intent.get("reason", "")).find("adaptation") < 0:
		_fail("BehaviorBrain adaptive hunger intent did not explain adaptation: %s" % JSON.stringify(adapted_hungry_decision))
		return
	var profile_hungry_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	profile_hungry_state["hunger"] = 78
	var profile_hungry_decision = threshold_brain.decide({
		"busy": false,
		"state": profile_hungry_state,
		"memory": TestSupport.adaptive_memory([], 25, 0, 0),
		"profile": TestSupport.adaptive_profile(90, 10, "medium", "活泼", "entertainment", ["feed_success"]),
		"personality": TestSupport.adaptive_personality(50, 20, 50, 40),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(profile_hungry_decision.get("type", "")) != "prompt" or str(profile_hungry_decision.get("name", "")) != "hungry" or not TestSupport.decision_has_profile_reason(profile_hungry_decision) or int(profile_hungry_decision.get("adaptation", {}).get("hunger_threshold", 80)) >= 80:
		_fail("BehaviorBrain profile care tendency did not lower hunger threshold: %s" % JSON.stringify(profile_hungry_decision))
		return

	var plain_mood_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	plain_mood_state["mood"] = 45
	var plain_mood_decision = threshold_brain.decide({"busy": false, "state": plain_mood_state}, FIXED_ENTERTAINMENT_TIME)
	if str(plain_mood_decision.get("type", "")) == "prompt" and str(plain_mood_decision.get("name", "")) == "play":
		_fail("BehaviorBrain plain mood threshold should not trigger at 45: %s" % JSON.stringify(plain_mood_decision))
		return
	var adapted_mood_decision = threshold_brain.decide({
		"busy": false,
		"state": plain_mood_state,
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(adapted_mood_decision.get("type", "")) != "prompt" or str(adapted_mood_decision.get("name", "")) != "play":
		_fail("BehaviorBrain adaptive mood threshold did not trigger at 45: %s" % JSON.stringify(adapted_mood_decision))
		return
	var profile_mood_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
	profile_mood_state["mood"] = 38
	var profile_mood_decision = threshold_brain.decide({
		"busy": false,
		"state": profile_mood_state,
		"memory": TestSupport.adaptive_memory([], 25, 0, 0),
		"profile": TestSupport.adaptive_profile(10, 90, "high", "活泼", "entertainment", ["tease_success"]),
		"personality": TestSupport.adaptive_personality(50, 20, 50, 40),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(profile_mood_decision.get("type", "")) != "prompt" or str(profile_mood_decision.get("name", "")) != "play" or not TestSupport.decision_has_profile_reason(profile_mood_decision) or int(profile_mood_decision.get("adaptation", {}).get("play_threshold", 35)) <= 35:
		_fail("BehaviorBrain profile play tendency did not raise play threshold: %s" % JSON.stringify(profile_mood_decision))
		return

	adaptive_brain.set_mode("安静")
	var quiet_decision = adaptive_brain.decide({
		"busy": false,
		"state": TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 80, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(quiet_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not add quiet mode actions: %s" % JSON.stringify(quiet_decision))
		return
	adaptive_brain.set_mode("活泼")
	var busy_decision = adaptive_brain.decide({
		"busy": true,
		"state": TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(busy_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not bypass busy state: %s" % JSON.stringify(busy_decision))
		return
	adaptive_brain.set_paused(true)
	var paused_decision = adaptive_brain.decide({
		"busy": false,
		"state": TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME),
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
	}, FIXED_ENTERTAINMENT_TIME)
	if str(paused_decision.get("type", "")) != "none":
		_fail("BehaviorBrain adaptation should not bypass paused state: %s" % JSON.stringify(paused_decision))
		return
	adaptive_brain.set_paused(false)
	var rest_decision = adaptive_brain.decide({
		"busy": false,
		"state": TestSupport.calm_state(local_rest_time),
		"memory": TestSupport.adaptive_memory(["tease_success"], 85, 10, 80),
		"profile": TestSupport.adaptive_profile(10, 90, "high", "活泼", "rest", ["tease_success"]),
		"personality": TestSupport.adaptive_personality(95, 25, 20, 90),
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
	var calm_state = TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)
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
	var recent_state = TestSupport.calm_state(forced_now)
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


	var observed_brain = BehaviorBrainScript.new()
	root_node.add_child(observed_brain)
	await process_frame
	observed_brain.configure(behavior_config)
	observed_brain.set_mode("活泼")
	var observed := {"decision": {}}
	observed_brain.decision_observed.connect(func(decision, _context): observed["decision"] = decision)
	observed_brain.set_context_provider(func(): return {"busy": true, "state": TestSupport.calm_state(FIXED_ENTERTAINMENT_TIME)})
	observed_brain._decide()
	if str(observed["decision"].get("type", "")) != "none" or str(observed["decision"].get("reason", "")) != "busy":
		_fail("BehaviorBrain decision_observed did not expose the busy none decision: %s" % JSON.stringify(observed))
		return

	var events_before_scenario = event_store.all_events().size()
	var direct_runner = CompanionScenarioRunnerScript.new()
	direct_runner.configure(behavior_config, {}, TestSupport.adaptive_personality(70, 20, 60, 40), event_store)
	var direct_result = direct_runner.run("all")
	if bool(direct_result.get("mutated_events", true)) or event_store.all_events().size() != events_before_scenario:
		_fail("CompanionScenarioRunner mutated events: %s" % JSON.stringify(direct_result))
		return
	var direct_scenarios = direct_result.get("scenarios", [])
	if typeof(direct_scenarios) != TYPE_ARRAY or direct_scenarios.size() != 11:
		_fail("CompanionScenarioRunner did not return all scenarios: %s" % JSON.stringify(direct_result))
		return
	for scenario in direct_scenarios:
		if typeof(scenario) != TYPE_DICTIONARY or not bool(scenario.get("passed", false)):
			_fail("CompanionScenarioRunner scenario failed: %s" % JSON.stringify(direct_result))
			return

	var scenario_config_store = ConfigStoreScript.new()
	root_node.add_child(scenario_config_store)
	scenario_config_store.configure()
	var scenario_main = MainScript.new()
	scenario_main.config_store = scenario_config_store
	scenario_main.behavior_manifest = behavior_config
	scenario_main.companion_event_store = event_store
	scenario_main.companion_scenario_result_path = config_dir.path_join("companion_scenario_result.json")
	scenario_main.dialogue_tone = "calm"
	var main_result = scenario_main._run_companion_scenarios("all")
	if bool(main_result.get("mutated_events", true)) or event_store.all_events().size() != events_before_scenario:
		_fail("Main companion scenario replay mutated events: %s" % JSON.stringify(main_result))
		return
	var main_scenarios = main_result.get("scenarios", [])
	if typeof(main_scenarios) != TYPE_ARRAY or main_scenarios.size() != 11:
		_fail("Main companion scenario replay did not return all scenarios: %s" % JSON.stringify(main_result))
		return
	for scenario in main_scenarios:
		if typeof(scenario) != TYPE_DICTIONARY or not bool(scenario.get("passed", false)):
			_fail("Main companion scenario failed: %s" % JSON.stringify(main_result))
			return
	var scenario_file = TestSupport.load_json(scenario_main.companion_scenario_result_path)
	if scenario_file.get("scenarios", []).size() != 11:
		_fail("Main companion scenario result file was not written: %s" % JSON.stringify(scenario_file))
		return
	scenario_main.free()
	scenario_config_store.free()

	print("Godot behavior test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
