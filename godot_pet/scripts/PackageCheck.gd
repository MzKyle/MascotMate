extends RefCounted

# Activated only by --package-check. Runs against the exported app and real display.
func run(main, report_path: String) -> void:
	var tree = main.get_tree()
	await tree.create_timer(0.3).timeout
	var checks := {}
	var startup_settings = {"display_scale": main.display_scale, "gravity_enabled": main.gravity_enabled, "behavior_mode": main.behavior_mode}
	await RenderingServer.frame_post_draw
	var rendered = main.get_viewport().get_texture().get_image()
	checks["transparent_render"] = rendered != null and rendered.get_pixel(0, 0).a < 0.01 and rendered.get_used_rect().has_area()
	checks["rendered_skin"] = main.pet_sprite.sprite.texture != null
	checks["shared_data_dir"] = main.state_store.state_path.get_base_dir() == main.config_store.config_dir and main.screenshot_pins.config_dir == main.config_store.config_dir
	checks["transparent_window"] = main.get_window().transparent and main.get_viewport().transparent_bg
	checks["window_flags"] = main.get_window().borderless and main.get_window().always_on_top
	main._on_right_clicked(Vector2.ZERO)
	await tree.process_frame
	checks["menu"] = main.menu_controller.popup.visible and main.menu_controller.popup.item_count > 10
	main.menu_controller.popup.hide()
	main._set_display_scale(1.25)
	main._set_gravity_enabled(false)
	var config_probe = preload("res://scripts/ConfigStore.gd").new()
	config_probe.configure()
	checks["persisted_settings"] = config_probe.app_config()["display_scale"] == 1.25 and config_probe.app_config()["gravity_enabled"] == false
	config_probe.free()
	var center = main.window_controller.play_area().get_center()
	main._on_grab_started(center)
	main._on_grab_moved(center + Vector2(20, 10))
	checks["grab"] = main.physics.state == "Grabbed"
	main._on_grab_released(Vector2(600, 0), true, center)
	checks["throw"] = main.physics.state == "Flinging"
	for edge in ["left", "right", "top", "bottom"]:
		main._enter_peek_mode(edge)
		checks["peek_" + edge] = main.peek_mode and main.peek_controller.sprite.texture != null
		main._exit_peek_mode(false)
	# Capture the actual desktop, exercise region selection, then the clipboard helper and pin windows.
	var screen = main.screenshot_pins._mouse_screen()
	var capture = DisplayServer.screen_get_image(screen)
	checks["screen_capture"] = capture != null and not capture.is_empty()
	if checks["screen_capture"]:
		var selector = preload("res://scripts/ScreenshotSelectionWindow.gd").new()
		main.add_child(selector)
		selector.open_with_capture(capture, Rect2i(Vector2i.ZERO, capture.get_size()))
		var selection := {"image": null}
		selector.selection_finished.connect(func(accepted, image):
			if accepted:
				selection["image"] = image
		)
		await tree.process_frame
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(20, 20)
		selector.layer._gui_input(press)
		var release = InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = Vector2(100, 100)
		selector.layer._gui_input(release)
		checks["region_selection"] = selection["image"] != null
		selector.queue_free()
		var crop = selection["image"]
		if crop != null:
			DirAccess.make_dir_recursive_absolute(main.screenshot_pins.screenshot_dir)
			var image_path = main.screenshot_pins.screenshot_dir.path_join("package-check.png")
			checks["screenshot_save"] = crop.save_png(image_path) == OK
			checks["clipboard"] = main.screenshot_pins._copy_image_to_clipboard(image_path)
			main.screenshot_pins._add_history(image_path)
			var paste_key = InputEventKey.new()
			paste_key.pressed = true
			paste_key.keycode = KEY_F3
			main.screenshot_pins.handle_input(paste_key)
			checks["image_pin"] = main.screenshot_pins.pins.size() == 1
			var close_key = InputEventKey.new()
			close_key.pressed = true
			close_key.keycode = KEY_F4
			main.screenshot_pins.handle_input(close_key)
			await tree.process_frame
			checks["close_pin"] = main.screenshot_pins.pins.is_empty()
	main.state_store.flush_save()
	var report = {"version": ProjectSettings.get_setting("application/config/version"), "checks": checks, "startup_settings": startup_settings, "data_dir": main.config_store.config_dir, "resource_root": main.repo_root, "window": main.window_controller.debug_state()}
	var passed = checks.size() >= 18 and not checks.values().has(false)
	report["passed"] = passed
	preload("res://scripts/AtomicJson.gd").write_dictionary(report_path, report)
	tree.quit(0 if passed else 1)
