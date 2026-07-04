extends Node2D

const PetSpriteScript = preload("res://scripts/PetSprite.gd")
const PetPhysicsScript = preload("res://scripts/PetPhysics.gd")
const InteractionScript = preload("res://scripts/InteractionController.gd")
const BehaviorBrainScript = preload("res://scripts/BehaviorBrain.gd")
const MiniGamesScript = preload("res://scripts/MiniGames.gd")
const StateStoreScript = preload("res://scripts/StateStore.gd")
const ScreenshotPinsScript = preload("res://scripts/ScreenshotPins.gd")
const ConfigStoreScript = preload("res://scripts/ConfigStore.gd")
const PetMenuControllerScript = preload("res://scripts/PetMenuController.gd")
const PeekControllerScript = preload("res://scripts/PeekController.gd")
const MischiefControllerScript = preload("res://scripts/MischiefController.gd")
const FeedbackEffectsScript = preload("res://scripts/FeedbackEffects.gd")
const SkinManagerScript = preload("res://scripts/SkinManager.gd")
const AnimationResolverScript = preload("res://scripts/AnimationResolver.gd")
const SkinStoreBridgeScript = preload("res://scripts/SkinStoreBridge.gd")
const CompanionEventStoreScript = preload("res://scripts/CompanionEventStore.gd")
const CompanionMemoryScript = preload("res://scripts/CompanionMemory.gd")
const CompanionExpressionBankScript = preload("res://scripts/CompanionExpressionBank.gd")

const HIDE_EDGE_THRESHOLD := 52.0
const PEEK_WINDOW_SIZE := Vector2i(112, 140)

var repo_root := ""
var manifest := {}
var behavior_manifest := {}
var config_store
var pet_sprite
var physics
var interaction
var brain
var mini_games
var state_store
var screenshot_pins
var menu_controller
var peek_controller
var mischief_controller
var feedback
var skin_manager
var animation_resolver
var skin_store_bridge
var companion_event_store
var companion_memory
var companion_expression_bank
var display_scale := 1.0
var drag_offset := Vector2.ZERO
var landing_squash := 0.0
var rng := RandomNumberGenerator.new()
var transparent_window := false
var mouse_passthrough_enabled := false
var gravity_enabled := true
var peek_mode := false
var peek_edge := ""
var behavior_mode := "安静"
var mischief_grab_active := false
var configured_skin_id := "classic_shinchan"
var feedback_window_until := 0.0
var tease_reward_recorded := false
var tease_nudge := Vector2.ZERO


func _ready() -> void:
	rng.randomize()
	repo_root = _resolve_repo_root()
	manifest = _load_json("res://assets/actions.json")
	behavior_manifest = _load_json("res://assets/behavior.json")

	config_store = ConfigStoreScript.new()
	add_child(config_store)
	config_store.configure()
	var app_config = config_store.app_config()
	display_scale = clamp(float(app_config.get("display_scale", 1.0)), 1.0, 1.5)
	gravity_enabled = bool(app_config.get("gravity_enabled", true))
	configured_skin_id = str(app_config.get("skin_id", "classic_shinchan"))

	_configure_window()
	_create_nodes()
	_play_capability("resting")
	_sync_window_size(true)
	physics.set_position_from_window(Vector2(get_window().position))
	physics.set_gravity_enabled(gravity_enabled)
	if transparent_window:
		show_bubble("透明桌宠模式启动：%s。" % skin_manager.selected_skin_name())
	else:
		show_bubble("Godot 安全窗口模式启动：%s。" % skin_manager.selected_skin_name())


func _input(event: InputEvent) -> void:
	if screenshot_pins != null and screenshot_pins.handle_input(event):
		return
	if mischief_grab_active:
		if event is InputEventMouseButton and event.pressed and mischief_controller.stop_rect().has_point(event.position):
			_stop_mischief_grab()
		return
	if mini_games != null and mini_games.handle_input(event):
		return
	if interaction != null and interaction.handle_input(event):
		return


func _process(delta: float) -> void:
	pet_sprite.update_animation(delta)
	_update_feedback_window_state()
	if mischief_grab_active:
		mischief_controller.tick(delta, get_window())
		_update_pet_pose(delta)
		_update_mouse_passthrough()
		return
	mini_games.tick(delta)
	_decay_tease_nudge(delta)
	physics.tick(delta, _play_area(), Vector2(get_window().size), _movement_contact_rect())
	_sync_walk_animation_to_velocity()
	get_window().position = Vector2i(round(physics.position.x), round(physics.position.y))
	_update_pet_pose(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state_store != null and state_store.has_method("flush_save"):
			state_store.flush_save()
		if companion_event_store != null and companion_event_store.has_method("flush_save"):
			companion_event_store.flush_save()
		if companion_memory != null and companion_memory.has_method("flush_save"):
			companion_memory.flush_save()
		if skin_store_bridge != null:
			skin_store_bridge.stop()
		get_tree().quit()


func _configure_window() -> void:
	var window = get_window()
	var safe_window = _env_flag("CRAYON_PET_SAFE_WINDOW", false)
	transparent_window = _env_flag("CRAYON_PET_TRANSPARENT", true) and not safe_window
	mouse_passthrough_enabled = _env_flag("CRAYON_PET_MOUSE_PASSTHROUGH", true)
	window.borderless = _env_flag("CRAYON_PET_BORDERLESS", transparent_window)
	window.always_on_top = _env_flag("CRAYON_PET_ALWAYS_ON_TOP", transparent_window)
	window.transparent = transparent_window
	window.unresizable = true
	get_viewport().transparent_bg = transparent_window
	if transparent_window:
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	else:
		RenderingServer.set_default_clear_color(Color(0.96, 0.94, 0.88, 1))


func _create_nodes() -> void:
	state_store = StateStoreScript.new()
	add_child(state_store)

	companion_event_store = CompanionEventStoreScript.new()
	add_child(companion_event_store)
	companion_event_store.configure(config_store.config_dir)

	companion_memory = CompanionMemoryScript.new()
	add_child(companion_memory)
	companion_memory.configure(config_store.config_dir, companion_event_store)

	companion_expression_bank = CompanionExpressionBankScript.new()
	add_child(companion_expression_bank)

	physics = PetPhysicsScript.new()
	add_child(physics)
	physics.landed.connect(_on_landed)
	physics.bounced.connect(_on_bounced)
	physics.attached_to_wall.connect(_on_attached_to_wall)

	skin_manager = SkinManagerScript.new()
	add_child(skin_manager)
	skin_manager.configure(repo_root, config_store.config_dir, manifest)
	skin_manager.select_skin(configured_skin_id)

	animation_resolver = AnimationResolverScript.new()
	add_child(animation_resolver)
	animation_resolver.configure(skin_manager.current_skin)

	pet_sprite = PetSpriteScript.new()
	add_child(pet_sprite)
	pet_sprite.configure_skin(skin_manager.current_skin, skin_manager.current_frame_root)
	pet_sprite.set_display_scale(display_scale)
	pet_sprite.action_finished.connect(_on_action_finished)

	peek_controller = PeekControllerScript.new()
	add_child(peek_controller)
	peek_controller.configure(repo_root)

	mini_games = MiniGamesScript.new()
	add_child(mini_games)
	mini_games.configure(repo_root, pet_sprite)
	mini_games.feed_success.connect(_on_feed_success)
	mini_games.tease_success.connect(_on_tease_success)
	mini_games.game_finished.connect(_on_game_finished)

	interaction = InteractionScript.new()
	add_child(interaction)
	interaction.single_clicked.connect(_on_single_clicked)
	interaction.double_clicked.connect(_on_double_clicked)
	interaction.right_clicked.connect(_on_right_clicked)
	interaction.wheel_used.connect(_show_status)
	interaction.grab_started.connect(_on_grab_started)
	interaction.grab_moved.connect(_on_grab_moved)
	interaction.grab_released.connect(_on_grab_released)

	brain = BehaviorBrainScript.new()
	add_child(brain)
	brain.configure(behavior_manifest)
	brain.set_context_provider(Callable(self, "_behavior_context"))
	brain.set_skin_behavior_profile(skin_manager.current_skin.get("behavior_profile", {}))
	brain.action_requested.connect(_on_behavior_action)
	brain.mischief_requested.connect(_on_mischief)
	brain.prompt_requested.connect(_on_behavior_prompt)
	brain.effect_requested.connect(_on_behavior_effect)
	brain.set_mode(behavior_mode)

	screenshot_pins = ScreenshotPinsScript.new()
	add_child(screenshot_pins)
	screenshot_pins.notify.connect(_on_screenshot_pins_notify)
	screenshot_pins.configure(repo_root, config_store)

	menu_controller = PetMenuControllerScript.new()
	add_child(menu_controller)
	menu_controller.command_requested.connect(_on_menu_command)

	mischief_controller = MischiefControllerScript.new()
	add_child(mischief_controller)
	mischief_controller.configure(pet_sprite, physics, Callable(self, "_play_area"), animation_resolver)
	mischief_controller.stop_requested.connect(_stop_mischief_grab)

	feedback = FeedbackEffectsScript.new()
	add_child(feedback)
	feedback.configure(repo_root, pet_sprite)
	feedback.temporary_window_extent_requested.connect(_on_feedback_window_requested)

	skin_store_bridge = SkinStoreBridgeScript.new()
	add_child(skin_store_bridge)
	skin_store_bridge.configure(repo_root, config_store.config_dir)
	skin_store_bridge.skin_requested.connect(_on_skin_store_skin_requested)
	skin_store_bridge.notify.connect(_on_skin_store_notify)


func _sync_window_size(keep_position := false) -> void:
	var window = get_window()
	var old_center = Vector2(window.position) + Vector2(window.size) * 0.5
	var desired = _desired_window_size()
	window.size = desired
	if keep_position:
		window.position = Vector2i(old_center - Vector2(desired) * 0.5)
	pet_sprite.position = _pet_default_position(Vector2(desired))
	mini_games.position = Vector2.ZERO
	feedback.set_window_size(Vector2(desired))
	feedback.set_bubble_position(_feedback_bubble_position(Vector2(desired)))
	mischief_controller.position_stop_button(window.size)
	_update_mouse_passthrough()


func _desired_window_size() -> Vector2i:
	if peek_mode:
		return PEEK_WINDOW_SIZE
	if pet_sprite == null:
		return get_window().size
	if mini_games != null and mini_games.active == "feed":
		var desired = pet_sprite.padded_window_size()
		desired.x = max(desired.x, 420)
		desired.y = max(desired.y, 260)
		return desired
	if mischief_grab_active or _feedback_window_active():
		return pet_sprite.padded_window_size()
	return pet_sprite.compact_window_size()


func _pet_default_position(window_size: Vector2) -> Vector2:
	if pet_sprite == null:
		return window_size * 0.5
	if peek_mode or mischief_grab_active:
		return window_size * 0.5
	return pet_sprite.compact_pet_position(window_size)


func _pet_pose_position(window_size: Vector2) -> Vector2:
	var position = _pet_default_position(window_size)
	if not peek_mode and not mischief_grab_active:
		position += tease_nudge
	return position


func _feedback_bubble_position(window_size: Vector2) -> Vector2:
	if peek_mode:
		return Vector2(8, 8)
	if mischief_grab_active:
		return Vector2(16, 48)
	return Vector2(14, max(8.0, min(14.0, window_size.y * 0.08)))


func _update_pet_pose(delta: float) -> void:
	if peek_mode:
		_apply_peek_pose()
		return
	if mischief_grab_active:
		mischief_controller.apply_pose(Vector2(get_window().size))
		feedback.set_bubble_position(Vector2(16, 48))
		return
	if landing_squash > 0.0:
		pet_sprite.position = _pet_pose_position(Vector2(get_window().size))
		landing_squash = max(0.0, landing_squash - delta * 3.2)
		pet_sprite.squash(landing_squash)
	elif physics.state == "Flinging" or physics.state == "Falling":
		pet_sprite.position = _pet_pose_position(Vector2(get_window().size))
		pet_sprite.lean_from_velocity(physics.velocity)
	elif physics.state == "Grabbed":
		pet_sprite.position = _pet_pose_position(Vector2(get_window().size))
		pet_sprite.sprite.rotation = sin(Time.get_ticks_msec() / 90.0) * 0.10
	elif physics.state == "WallAttached" or physics.state == "EdgeWalk":
		_apply_wall_walk_pose()
	else:
		pet_sprite.position = _pet_pose_position(Vector2(get_window().size))
		pet_sprite.reset_transform()


func _play_area() -> Rect2:
	var screen = DisplayServer.window_get_current_screen()
	return Rect2(
		Vector2(DisplayServer.screen_get_position(screen)),
		Vector2(DisplayServer.screen_get_size(screen))
	)


func _movement_contact_rect() -> Rect2:
	var window_size = Vector2(get_window().size)
	if peek_mode or pet_sprite == null:
		return Rect2(Vector2.ZERO, window_size)
	if mini_games != null and mini_games.active == "feed":
		return Rect2(Vector2.ZERO, window_size)

	var rect = _pet_visible_rect_for_physics()
	var anchor = _pet_anchor_position_for_physics(window_size, rect)
	return Rect2(anchor + rect.position, rect.size)


func _pet_visible_rect_for_physics() -> Rect2:
	if physics == null:
		return pet_sprite.visible_rect()
	if (physics.state == "WallAttached" or physics.state == "EdgeWalk") and physics.wall_side != 0:
		return pet_sprite.visible_rect_for_rotation(_wall_pose_rotation())
	if physics.state == "Flinging" or physics.state == "Falling":
		var rotation = clamp(physics.velocity.x / 1800.0, -0.35, 0.35)
		return pet_sprite.visible_rect_for_rotation(rotation)
	return pet_sprite.visible_rect_for_rotation(0.0)


func _pet_anchor_position_for_physics(window_size: Vector2, visible_rect: Rect2) -> Vector2:
	var anchor = _pet_default_position(window_size)
	if physics == null:
		return anchor
	if (physics.state == "WallAttached" or physics.state == "EdgeWalk") and physics.wall_side != 0:
		if physics.wall_side > 0:
			anchor.x = -visible_rect.position.x
		else:
			anchor.x = window_size.x - visible_rect.position.x - visible_rect.size.x
	return anchor


func _on_single_clicked(local_pos: Vector2) -> void:
	if physics.state == "Grabbed":
		return
	if peek_mode:
		_exit_peek_mode(true)
		return
	var pet_local = pet_sprite.to_local(local_pos)
	if pet_local.y < pet_sprite.pet_rect().position.y + pet_sprite.pet_rect().size.y * 0.42:
		var before = state_store.snapshot()
		var changes = state_store.pet()
		_record_interaction("pet", "", {}, ["social", "positive"], before, state_store.snapshot())
		_show_expression("pet_head", "摸摸头。", 1.8, _format_changes(changes))
		feedback.spawn_heart()
	else:
		var before = state_store.snapshot()
		var changes = state_store.poke()
		_record_interaction("poke", "", {}, ["social"], before, state_store.snapshot())
		_show_expression("poke_body", "戳到了。", 1.8, _format_changes(changes))
		_jiggle()


func _on_double_clicked() -> void:
	if peek_mode:
		_exit_peek_mode(true)
	_start_tease_interaction()


func _on_right_clicked(_local_pos: Vector2) -> void:
	_show_menu()


func _on_grab_started(global_pos: Vector2) -> void:
	if peek_mode:
		_exit_peek_mode(false)
	_record_interaction("grab")
	brain.set_paused(true)
	drag_offset = get_viewport().get_mouse_position()
	physics.begin_grab(global_pos - drag_offset)
	_play_capability("held")
	_show_expression("grab_start", "抱起来啦。")


func _on_grab_moved(global_pos: Vector2) -> void:
	physics.update_grab(global_pos - drag_offset)


func _on_grab_released(velocity: Vector2, held: bool, global_pos: Vector2) -> void:
	var speed = velocity.length()
	brain.set_paused(false)
	var hide_edge = _hide_edge_for_release(global_pos)
	if held and hide_edge != "":
		_record_interaction("peek", "", {"edge": hide_edge}, ["peek"])
		_enter_peek_mode(hide_edge)
		return
	if speed > 420.0:
		_record_interaction("throw", "", {"speed": speed}, ["physics"])
		physics.release(velocity, true)
		_play_capability("falling")
		_show_expression("throw_fast", "飞出去啦！")
	else:
		physics.release(velocity, false)
		if held:
			_record_interaction("release")
			_show_expression("release_soft", "轻轻放下。")


func _on_landed() -> void:
	landing_squash = 0.25
	show_bubble("落地。")
	await get_tree().create_timer(0.45).timeout
	physics.idle()
	_play_capability("resting")


func _on_bounced() -> void:
	landing_squash = 0.12
	_sync_walk_animation_to_velocity()


func _on_attached_to_wall(_side: int) -> void:
	_play_wall_walk_action()
	show_bubble("贴到边边了。")


func _on_action_finished(next_action: String) -> void:
	if next_action != "":
		if not pet_sprite.play(next_action):
			_play_capability("resting")
		_sync_window_size(true)


func _on_behavior_action(action_name: String) -> void:
	if _busy():
		return
	match action_name:
		"walk":
			var dir = -1 if rng.randf() < 0.5 else 1
			physics.start_walk(dir, 95.0)
			_sync_walk_animation_to_velocity(true)
		"idle":
			physics.idle()
			_play_capability("resting")
		"edge":
			var side = -1 if rng.randf() < 0.5 else 1
			physics.attach_to_wall(side)
			physics.start_edge_walk(70.0 if rng.randf() < 0.5 else -70.0)
			_play_wall_walk_action()
		"sleep":
			physics.idle()
			_play_capability("sleeping")
			state_store.sleep_tick()
			_sync_window_size(true)
		"companion":
			physics.idle()
			_play_capability("companion")
			_sync_window_size(true)
		"invite":
			_show_expression("auto_prompt:play", "要不要玩一会儿？")


func _on_behavior_prompt(kind: String, message: String) -> void:
	if kind == "hungry":
		feedback.spawn_note()
	_show_expression("auto_prompt:%s" % kind, message, 2.4)


func _on_behavior_effect(kind: String) -> void:
	if kind == "note":
		feedback.spawn_note()
	elif kind == "footprint":
		feedback.spawn_footprint()


func _on_mischief(kind: String) -> void:
	if behavior_mode != "捣乱":
		return
	if kind == "grab":
		if not _start_mischief_grab():
			brain.request_forced_mischief("grab", 1.0, 4.0)
	elif kind == "note":
		feedback.spawn_note()
	else:
		feedback.spawn_footprint()


func _on_feed_success() -> void:
	var before = state_store.snapshot()
	var changes = state_store.feed()
	_record_interaction("feed", "", {"result": "success"}, ["care", "food", "positive"], before, state_store.snapshot())
	_play_capability("feeding")
	_sync_window_size(true)
	_show_expression("feed_success", "吃到啦。", 1.8, _format_changes(changes))


func _on_tease_success(count: int, direction: Vector2) -> void:
	_apply_tease_nudge(direction, count)
	if not tease_reward_recorded:
		tease_reward_recorded = true
		var before = state_store.snapshot()
		var changes = state_store.play()
		_record_interaction("play", "", {"count": count}, ["play", "positive"], before, state_store.snapshot())
		_show_expression("tease_success", "嘿嘿，别挠啦。", 1.4, _format_changes(changes))
	elif count >= 3:
		_show_expression("tease_done", "玩够啦。", 1.3)
	if count >= 2:
		feedback.spawn_heart()


func _on_game_finished(name: String) -> void:
	call_deferred("_sync_window_size", true)
	if name == "feed":
		feedback.spawn_heart()


func _start_tease_interaction() -> void:
	if mini_games == null:
		return
	if peek_mode:
		_exit_peek_mode(true)
	mini_games.start_tease()
	_record_interaction("", "tease_start", {}, ["play"])
	tease_reward_recorded = false
	tease_nudge = Vector2.ZERO
	_sync_window_size(true)
	_update_mouse_passthrough()
	_show_expression("tease_start", "来逗我呀。", 1.4)


func _apply_tease_nudge(direction: Vector2, count: int) -> void:
	var dodge_direction = direction
	if dodge_direction.length() <= 0.001:
		dodge_direction = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.35, 0.35))
	if dodge_direction.length() <= 0.001:
		dodge_direction = Vector2.RIGHT
	var distance = 8.0 + float(min(count, 3)) * 2.0
	tease_nudge = -dodge_direction.normalized() * distance


func _decay_tease_nudge(delta: float) -> void:
	if tease_nudge.length_squared() <= 0.01:
		tease_nudge = Vector2.ZERO
		return
	tease_nudge = tease_nudge.lerp(Vector2.ZERO, min(1.0, delta * 8.0))


func _show_status() -> void:
	var s = state_store.state
	show_bubble("心情 %d / 饥饿 %d / 体力 %d / 亲密 %d" % [s["mood"], s["hunger"], s["energy"], s["affection"]], 3.0)


func _on_screenshot_pins_notify(text: String) -> void:
	show_bubble(text, 2.2)


func _show_menu() -> void:
	menu_controller.show_menu(gravity_enabled, peek_mode, behavior_mode)


func _on_menu_command(command: String) -> void:
	match command:
		"walk":
			_record_interaction("menu_walk")
			_on_behavior_action("walk")
		"feed":
			_record_interaction("menu_feed", "feed_start", {"command": "feed"}, ["care", "food"])
			mini_games.start_feed()
			_sync_window_size(true)
			_update_mouse_passthrough()
		"sleep":
			_record_interaction("sleep")
			_play_capability("sleeping")
			physics.idle()
			state_store.sleep_tick()
			_sync_window_size(true)
		"wake":
			_record_interaction("wake")
			_play_capability("waking")
			_sync_window_size(true)
		"tease":
			_start_tease_interaction()
		"scale_100":
			_set_display_scale(1.0)
		"scale_125":
			_set_display_scale(1.25)
		"scale_150":
			_set_display_scale(1.5)
		"toggle_gravity":
			_set_gravity_enabled(not gravity_enabled)
		"exit_peek":
			_exit_peek_mode(true)
		"skins":
			_open_skin_manager()
		"screenshot_settings":
			screenshot_pins.open_settings()
		"mode_quiet":
			_set_behavior_mode("安静")
		"mode_active":
			_set_behavior_mode("活泼")
		"mode_mischief":
			_set_behavior_mode("捣乱")
		"clear_mischief":
			feedback.clear_mischief()
		"exit":
			get_tree().quit()


func _set_behavior_mode(value: String, announce := true) -> void:
	var next_mode = value if value in ["安静", "活泼", "捣乱"] else "安静"
	var previous_mode = behavior_mode
	behavior_mode = next_mode
	if brain != null:
		brain.set_mode(next_mode)
		if next_mode == "捣乱":
			brain.request_forced_mischief("grab", 0.8, 6.0)
	if next_mode != "捣乱":
		_stop_mischief_grab(false)
	if announce:
		_show_expression("mode_changed", "%s模式。" % next_mode, 1.8, "", {"mode": next_mode})
	if next_mode != previous_mode:
		_record_interaction("", "mode_changed", {"from": previous_mode, "to": next_mode}, ["mode"])


func _set_display_scale(scale: float) -> void:
	display_scale = clamp(scale, 1.0, 1.5)
	pet_sprite.set_display_scale(display_scale)
	if config_store != null:
		config_store.set_app_config({"display_scale": display_scale})
	_sync_window_size(true)
	_update_mouse_passthrough()
	show_bubble("显示大小 %d%%" % int(display_scale * 100))


func _set_gravity_enabled(value: bool) -> void:
	gravity_enabled = value
	if config_store != null:
		config_store.set_app_config({"gravity_enabled": value})
	physics.set_gravity_enabled(value)
	if value:
		if not peek_mode and physics.state != "Grabbed":
			physics.release(Vector2.ZERO, false)
		show_bubble("重力开启，会落地。")
	else:
		show_bubble("重力关闭，悬浮模式。")


func _open_skin_manager() -> void:
	if skin_store_bridge != null and skin_store_bridge.open_store():
		return
	show_bubble("皮肤商店启动失败，请检查 helper。", 2.8)


func _set_skin(skin_id: String) -> void:
	if skin_manager == null or pet_sprite == null:
		return
	if peek_mode:
		_exit_peek_mode(false)
	if mini_games != null:
		mini_games.clear()
	if not skin_manager.select_skin(skin_id):
		show_bubble("皮肤不可用。")
		return
	animation_resolver.configure(skin_manager.current_skin)
	if brain != null:
		brain.set_skin_behavior_profile(skin_manager.current_skin.get("behavior_profile", {}))
	pet_sprite.configure_skin(skin_manager.current_skin, skin_manager.current_frame_root)
	pet_sprite.set_display_scale(display_scale)
	_play_capability("resting")
	if config_store != null:
		config_store.set_app_config({"skin_id": skin_manager.selected_skin_id()})
	_sync_window_size(true)
	_update_mouse_passthrough()
	show_bubble("已切换：%s。" % skin_manager.selected_skin_name())


func _on_skin_store_skin_requested(skin_id: String) -> void:
	if skin_manager != null:
		skin_manager.reload_skins()
	_set_skin(skin_id)


func _on_skin_store_notify(message: String) -> void:
	show_bubble(message, 2.8)


func _start_mischief_grab() -> bool:
	if behavior_mode != "捣乱" or _busy():
		return false
	mischief_grab_active = true
	brain.set_paused(true)
	mischief_controller.start()
	_sync_window_size(true)
	mischief_controller.tick(0.0, get_window())
	show_bubble("嘿嘿，鼠标借我一下。", 1.25)
	_update_mouse_passthrough()
	return true


func _stop_mischief_grab(announce := true) -> void:
	if not mischief_grab_active:
		return
	mischief_grab_active = false
	mischief_controller.stop()
	brain.set_paused(false)
	physics.set_position_from_window(Vector2(get_window().position))
	physics.idle()
	_play_capability("resting")
	pet_sprite.reset_transform()
	_sync_window_size(true)
	_update_mouse_passthrough()
	if announce:
		show_bubble("好吧，还给你。")


func _sync_walk_animation_to_velocity(force := false) -> void:
	if physics == null or pet_sprite == null:
		return
	if physics.state != "Walk":
		return
	if abs(physics.velocity.x) < 1.0:
		return
	var desired = "walk_right" if physics.velocity.x > 0.0 else "walk_left"
	desired = animation_resolver.resolve("locomotion", {"direction": "right" if physics.velocity.x > 0.0 else "left"})
	if force or pet_sprite.current_action != desired:
		if desired != "":
			if pet_sprite.play(desired):
				_sync_window_size(true)


func _play_wall_walk_action() -> void:
	var desired = _wall_walk_action()
	if pet_sprite.current_action != desired:
		if desired != "":
			if pet_sprite.play(desired):
				_sync_window_size(true)


func _apply_wall_walk_pose() -> void:
	if physics.wall_side == 0:
		return
	_play_wall_walk_action()
	pet_sprite.sprite.scale = pet_sprite._base_sprite_scale()
	pet_sprite.sprite.rotation = _wall_pose_rotation()
	var rect = _pet_visible_rect_for_physics()
	pet_sprite.position = _pet_anchor_position_for_physics(Vector2(get_window().size), rect)


func _wall_walk_action() -> String:
	var direction := "right"
	if abs(physics.velocity.y) < 1.0:
		direction = "right" if physics.wall_side > 0 else "left"
		return animation_resolver.resolve("edge", {"direction": direction})
	if physics.wall_side > 0:
		direction = "right" if physics.velocity.y > 0.0 else "left"
	else:
		direction = "left" if physics.velocity.y > 0.0 else "right"
	return animation_resolver.resolve("edge", {"direction": direction})


func _wall_pose_rotation() -> float:
	if pet_sprite != null and bool(pet_sprite.current_config.get("native_edge_pose", false)):
		return 0.0
	if physics == null or physics.wall_side <= 0:
		return -PI * 0.5
	return PI * 0.5


func _play_capability(capability: String, constraints: Dictionary = {}) -> bool:
	if pet_sprite == null:
		return false
	var played := false
	if animation_resolver != null:
		var action_id = animation_resolver.resolve(capability, constraints)
		if action_id != "":
			played = pet_sprite.play(action_id)
	if not played:
		played = pet_sprite.play(capability)
	if played:
		_sync_window_size(true)
	return played


func show_bubble(text: String, seconds := 1.8) -> void:
	if feedback != null:
		feedback.show_bubble(text, seconds)


func _show_expression(key: String, fallback_text: String, seconds := 1.8, suffix := "", context := {}) -> void:
	var expression_context = _expression_context(context)
	if companion_expression_bank == null or not companion_expression_bank.has_method("resolve"):
		show_bubble(fallback_text + suffix, seconds)
		_record_expression(key, fallback_text)
		return
	var expression = companion_expression_bank.resolve(key, expression_context, fallback_text, seconds)
	var text = str(expression.get("text", fallback_text))
	show_bubble(text + suffix, float(expression.get("seconds", seconds)))
	_record_expression(key, text)


func _expression_context(context := {}) -> Dictionary:
	var result := {}
	if companion_memory != null and companion_memory.has_method("expression_context"):
		result = companion_memory.expression_context({})
	if typeof(context) == TYPE_DICTIONARY:
		for key in context.keys():
			result[key] = context[key]
	result["mode"] = str(result.get("mode", behavior_mode))
	result["skin_id"] = skin_manager.selected_skin_id() if skin_manager != null and skin_manager.has_method("selected_skin_id") else ""
	result["state"] = state_store.snapshot() if state_store != null and state_store.has_method("snapshot") else {}
	var personality = _selected_personality()
	result["personality"] = personality
	result["tone"] = str(personality.get("tone", "short_cute"))
	return result


func _record_expression(key: String, text: String) -> void:
	if companion_memory != null and companion_memory.has_method("record_expression"):
		companion_memory.record_expression(key, text)


func _selected_personality() -> Dictionary:
	if skin_manager != null and skin_manager.has_method("selected_personality"):
		return skin_manager.selected_personality()
	return {}


func _on_feedback_window_requested(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var was_active = _feedback_window_active()
	var now = float(Time.get_ticks_msec()) / 1000.0
	feedback_window_until = max(feedback_window_until, now + seconds)
	if not was_active:
		_sync_window_size(true)
	else:
		_update_mouse_passthrough()


func _feedback_window_active() -> bool:
	return feedback_window_until > float(Time.get_ticks_msec()) / 1000.0


func _update_feedback_window_state() -> void:
	if feedback_window_until <= 0.0 or _feedback_window_active():
		return
	feedback_window_until = 0.0
	if not peek_mode and not mischief_grab_active and (mini_games == null or mini_games.active != "feed"):
		_sync_window_size(true)


func _update_mouse_passthrough() -> void:
	var window = get_window()
	if not transparent_window or not mouse_passthrough_enabled:
		window.mouse_passthrough_polygon = PackedVector2Array()
		return
	if mischief_grab_active:
		var rect = mischief_controller.stop_rect().grow(4.0)
		window.mouse_passthrough_polygon = _rect_polygon(rect)
		return
	if mini_games != null and mini_games.active != "":
		if mini_games.active == "tease":
			var visible_rect = pet_sprite.visible_rect()
			var rect = Rect2(pet_sprite.position + visible_rect.position, visible_rect.size).grow(10.0)
			rect = rect.intersection(Rect2(Vector2.ZERO, Vector2(window.size)))
			window.mouse_passthrough_polygon = _rect_polygon(rect) if rect.size.x > 1.0 and rect.size.y > 1.0 else PackedVector2Array()
			return
		var size = Vector2(window.size)
		window.mouse_passthrough_polygon = _rect_polygon(Rect2(Vector2.ZERO, size))
		return
	if peek_mode:
		var size = Vector2(window.size)
		window.mouse_passthrough_polygon = _rect_polygon(Rect2(Vector2.ZERO, size))
		return

	var visible_rect = pet_sprite.visible_rect()
	var rect = Rect2(pet_sprite.position + visible_rect.position, visible_rect.size).grow(10.0)
	rect = rect.intersection(Rect2(Vector2.ZERO, Vector2(window.size)))
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		window.mouse_passthrough_polygon = PackedVector2Array()
		return
	var cut = min(rect.size.x, rect.size.y) * 0.22
	window.mouse_passthrough_polygon = PackedVector2Array([
		rect.position + Vector2(cut, 0),
		rect.position + Vector2(rect.size.x - cut, 0),
		rect.position + Vector2(rect.size.x, cut),
		rect.position + Vector2(rect.size.x, rect.size.y - cut),
		rect.position + Vector2(rect.size.x - cut, rect.size.y),
		rect.position + Vector2(cut, rect.size.y),
		rect.position + Vector2(0, rect.size.y - cut),
		rect.position + Vector2(0, cut),
	])


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])


func _hide_edge_for_release(global_pos: Vector2) -> String:
	return peek_controller.edge_for_release(global_pos, _play_area(), HIDE_EDGE_THRESHOLD)


func _enter_peek_mode(edge: String) -> void:
	if mini_games != null:
		mini_games.clear()
	peek_mode = true
	peek_edge = edge
	brain.set_paused(true)
	physics.peek()
	peek_controller.enter(edge)
	pet_sprite.visible = false
	_sync_window_size(false)
	physics.position = _peek_window_position(edge, DisplayServer.mouse_get_position())
	get_window().position = Vector2i(round(physics.position.x), round(physics.position.y))
	_apply_peek_pose()
	_update_mouse_passthrough()


func _exit_peek_mode(show_message: bool) -> void:
	if not peek_mode:
		return
	var previous_edge = peek_edge
	peek_mode = false
	peek_edge = ""
	brain.set_paused(false)
	peek_controller.exit()
	pet_sprite.visible = true
	_play_capability("resting")
	_sync_window_size(false)
	var area = _play_area()
	var size = Vector2(get_window().size)
	physics.position = Vector2(
		clamp(physics.position.x, area.position.x, area.position.x + area.size.x - size.x),
		clamp(physics.position.y, area.position.y, area.position.y + area.size.y - size.y)
	)
	if gravity_enabled:
		physics.release(Vector2.ZERO, false)
	else:
		physics.idle()
	pet_sprite.position = _pet_default_position(size)
	pet_sprite.reset_transform()
	_update_mouse_passthrough()
	if show_message:
		_show_expression("peek_exit", "被发现啦。")
	_record_interaction("", "peek_exit", {"edge": previous_edge}, ["peek"])


func _peek_window_position(edge: String, global_pos: Vector2) -> Vector2:
	return peek_controller.window_position(edge, global_pos, _play_area(), Vector2(get_window().size))


func _apply_peek_pose() -> void:
	pet_sprite.visible = false
	peek_controller.apply_pose()
	feedback.set_bubble_position(Vector2(8, 8))


func _jiggle() -> void:
	var base = pet_sprite.position
	var offsets = [Vector2(-5, 0), Vector2(6, 0), Vector2(-3, 0), Vector2(0, 0)]
	for i in range(offsets.size()):
		await get_tree().create_timer(0.045).timeout
		pet_sprite.position = base + offsets[i]
	pet_sprite.position = base


func _busy() -> bool:
	return mischief_grab_active or physics.state in ["Grabbed", "Flinging", "Falling", "Landing", "Peeking"] or mini_games.active != ""


func _behavior_context() -> Dictionary:
	return {
		"mode": behavior_mode,
		"busy": _busy(),
		"physics_state": str(physics.state) if physics != null else "",
		"mini_game": str(mini_games.active) if mini_games != null else "",
		"peek_mode": peek_mode,
		"skin_id": skin_manager.selected_skin_id() if skin_manager != null and skin_manager.has_method("selected_skin_id") else "",
		"state": state_store.snapshot() if state_store != null and state_store.has_method("snapshot") else {},
		"state_store": state_store,
		"event_store": companion_event_store,
		"memory_store": companion_memory,
		"memory": companion_memory.snapshot() if companion_memory != null and companion_memory.has_method("snapshot") else {},
		"personality": _selected_personality(),
	}


func _record_interaction(legacy_kind: String, event_kind := "", meta := {}, tags := [], state_before := {}, state_after := {}) -> void:
	var clean_legacy = legacy_kind.strip_edges()
	if clean_legacy != "":
		if state_store != null and state_store.has_method("record_interaction"):
			state_store.record_interaction(clean_legacy)
		if brain != null and brain.has_method("record_interaction"):
			brain.record_interaction(clean_legacy)
	var clean_event_kind = event_kind.strip_edges()
	if clean_event_kind == "":
		clean_event_kind = _event_kind_for_interaction(clean_legacy)
	if clean_event_kind != "":
		_record_companion_event(clean_event_kind, "user", meta, tags, state_before, state_after)


func _record_companion_event(kind: String, source: String, meta := {}, tags := [], state_before := {}, state_after := {}) -> void:
	if companion_event_store == null or not companion_event_store.has_method("record_event"):
		return
	var event = companion_event_store.record_event(kind, source, _event_context(), meta, tags, state_before, state_after)
	if typeof(event) == TYPE_DICTIONARY and not event.is_empty() and companion_memory != null and companion_memory.has_method("refresh"):
		companion_memory.refresh()


func _event_context() -> Dictionary:
	return {
		"mode": behavior_mode,
		"physics_state": str(physics.state) if physics != null else "",
		"mini_game": str(mini_games.active) if mini_games != null else "",
		"peek_mode": peek_mode,
		"skin_id": skin_manager.selected_skin_id() if skin_manager != null and skin_manager.has_method("selected_skin_id") else "",
		"state": state_store.snapshot() if state_store != null and state_store.has_method("snapshot") else {},
		"memory": companion_memory.snapshot() if companion_memory != null and companion_memory.has_method("snapshot") else {},
		"personality": _selected_personality(),
	}


func _event_kind_for_interaction(legacy_kind: String) -> String:
	var mapping = {
		"pet": "pet_head",
		"poke": "poke_body",
		"grab": "grab_start",
		"release": "release_soft",
		"throw": "throw_fast",
		"peek": "peek_enter",
		"feed": "feed_success",
		"play": "tease_success",
	}
	return str(mapping.get(legacy_kind, legacy_kind))


func _format_changes(changes: Dictionary) -> String:
	var labels = {"mood": "心情", "hunger": "饥饿", "energy": "体力", "affection": "亲密"}
	var parts := []
	for key in changes.keys():
		var delta = int(changes[key])
		if delta != 0:
			parts.append("%s %+d" % [labels.get(key, key), delta])
	if parts.is_empty():
		return "状态没有变化。"
	return "，".join(parts)


func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _has_resource_root(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path.path_join("resource_hd"))


func _resolve_repo_root() -> String:
	var env = OS.get_environment("CRAYON_PET_ROOT")
	if env != "" and _has_resource_root(env):
		return env
	var candidates = [
		ProjectSettings.globalize_path("res://..").simplify_path(),
		OS.get_executable_path().get_base_dir().simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").simplify_path(),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("..").path_join("..").simplify_path(),
	]
	for candidate in candidates:
		if _has_resource_root(candidate):
			return candidate
	return ProjectSettings.globalize_path("res://..").simplify_path()


func _env_flag(name: String, default_value: bool) -> bool:
	var value = OS.get_environment(name).strip_edges().to_lower()
	if value == "":
		return default_value
	return value in ["1", "true", "yes", "on"]
