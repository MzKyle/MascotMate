extends SceneTree

const SkinManagerScript = preload("res://scripts/SkinManager.gd")
const PetSpriteScript = preload("res://scripts/PetSprite.gd")
const PetPhysicsScript = preload("res://scripts/PetPhysics.gd")
const PetWindowControllerScript = preload("res://scripts/PetWindowController.gd")
const MischiefControllerScript = preload("res://scripts/MischiefController.gd")
const TestSupport = preload("res://tests/TestSupport.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_node = get_root()
	var repo_root = TestSupport.repo_root()
	var config_dir = TestSupport.config_dir()
	if config_dir == "":
		_fail("CRAYON_PET_CONFIG_DIR is required for window tests.")
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

	var skin_manager = SkinManagerScript.new()
	root_node.add_child(skin_manager)
	skin_manager.configure(repo_root, config_dir, TestSupport.load_json("res://assets/actions.json"))
	if not skin_manager.select_skin("classic_shinchan"):
		_fail("Default skin could not be selected for MischiefController probe.")
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

	print("Godot window test passed.")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print(message)
	quit(1)
