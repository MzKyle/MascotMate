extends SceneTree

const MainScript = preload("res://scripts/Main.gd")
const ConsoleBridge = preload("res://scripts/CompanionConsoleBridge.gd")
const AtomicJson = preload("res://scripts/AtomicJson.gd")
const TestSupport = preload("res://tests/TestSupport.gd")


class LauncherProbe extends "res://scripts/HelperProcessLauncher.gd":
	var launches := 0
	var idle_timeout := "2"
	var opened_path := ""
	var reopened: Array[String] = []

	func _helper_command(args: PackedStringArray) -> Dictionary:
		launches += 1
		var helper_args := args.duplicate()
		helper_args[helper_args.find("--idle-timeout") + 1] = idle_timeout
		var fixture := repo_root.path_join("tests/fixtures/console_helper.py")
		var process_args := PackedStringArray([fixture, opened_path])
		process_args.append_array(helper_args)
		return {"program": OS.get_environment("MASCOTMATE_TEST_PYTHON"), "args": process_args}

	func _open_url(url: String) -> Error:
		reopened.append(url)
		return OK


class RefreshProbe extends RefCounted:
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1


var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := TestSupport.config_dir()
	if data_dir.is_empty() or OS.get_environment("MASCOTMATE_TEST_PYTHON").is_empty():
		push_error("The helper lifecycle test requires isolated data and the test Python executable.")
		quit(1)
		return
	var launcher := LauncherProbe.new()
	launcher.opened_path = data_dir.path_join("initial-browser-url.txt")
	var bridge = ConsoleBridge.new()
	bridge.helper_launcher = launcher
	root.add_child(bridge)
	bridge.configure(TestSupport.repo_root(), data_dir)
	var main = MainScript.new()
	main.companion_console_bridge = bridge
	main.companion_memory = RefreshProbe.new()
	main.companion_profile = RefreshProbe.new()
	var snapshot_path := data_dir.path_join("snapshot.json")
	main.companion_debug_snapshot_path = snapshot_path

	await _test_idle_and_reopen(bridge, launcher, main, snapshot_path)
	await _test_running_shutdown(bridge, launcher)
	main.free()
	if failures == 0:
		print("Godot helper lifecycle tests passed.")
	quit(0 if failures == 0 else 1)


func _test_idle_and_reopen(bridge, launcher: LauncherProbe, main, snapshot_path: String) -> void:
	_check(bridge.open_console(), "Start the real helper")
	var first_pid := launcher.helper_pid
	_check(bridge.open_console() and launcher.launches == 1, "Repeated opens during startup reuse the process")
	if not await _wait_for(func(): return FileAccess.file_exists(launcher.opened_path), "initial browser handoff"):
		return
	var url := FileAccess.get_file_as_string(launcher.opened_path)
	var previous_reopens := launcher.reopened.size()
	_check(bridge.open_console() and launcher.helper_pid == first_pid and launcher.launches == 1
		and launcher.reopened.size() == previous_reopens + 1 and launcher.reopened.back() == url,
		"Reopen the same browser URL with the original token")
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 3
	if request.request(url.replace("/companion/?", "/api/companion/snapshot?")) == OK:
		var response = await request.request_completed
		_check(response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200, "The reused token authorizes console requests")
	else:
		_check(false, "Send a request to the reopened console")
	request.queue_free()
	main._on_companion_debug_timer()
	var original := FileAccess.get_file_as_string(snapshot_path)
	_check(not original.is_empty(), "The diagnostic timer writes while the helper is live")

	if not await _wait_for(func(): return not OS.is_process_running(first_pid), "natural idle shutdown"):
		return
	_check(first_pid > 0 and launcher.helper_pid == first_pid, "The naturally exited child initially leaves a positive PID")
	main.behavior_mode = "活泼"
	main.companion_snapshot_error = ERR_FILE_CANT_WRITE
	main.companion_summary_date = ""
	main._on_companion_debug_timer()
	_check(launcher.helper_pid == -1 and not bridge.is_running(), "The timer clears a stale PID")
	_check(FileAccess.get_file_as_string(snapshot_path) == original, "An earlier write error does not keep the offline snapshot timer writing")
	_check(main.companion_memory.refreshes == 2 and main.companion_profile.refreshes == 2, "Daily maintenance still runs offline")
	main._on_behavior_decision_observed({}, {})
	_check(AtomicJson.read_dictionary(snapshot_path).get("runtime", {}).get("behavior_mode") == "活泼",
		"Event-driven snapshots still work offline")

	DirAccess.remove_absolute(launcher.opened_path)
	_check(bridge.open_console() and launcher.launches == 2 and launcher.helper_pid != first_pid, "Start a fresh console after idle exit")
	var second_pid := launcher.helper_pid
	if second_pid > 0 and await _wait_for(func(): return not OS.is_process_running(second_pid), "second idle shutdown"):
		bridge.stop()
		_check(launcher.helper_pid == -1, "Stopping an already exited helper clears its saved PID")


func _test_running_shutdown(bridge, launcher: LauncherProbe) -> void:
	if FileAccess.file_exists(launcher.opened_path):
		DirAccess.remove_absolute(launcher.opened_path)
	launcher.idle_timeout = "60"
	_check(bridge.open_console(), "Start a helper for shutdown")
	var pid := launcher.helper_pid
	if not await _wait_for(func(): return FileAccess.file_exists(launcher.opened_path), "running helper handoff"):
		bridge.free()
		return
	_check(bridge.is_running(), "The shutdown test starts with a live helper")
	bridge.free()
	_check(launcher.helper_pid == -1, "Leaving the scene clears the tracked PID")
	await _wait_for(func(): return not OS.is_process_running(pid), "helper shutdown before its normal idle timeout")


func _wait_for(condition: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 10_000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var completed: bool = condition.call()
	_check(completed, "Timed out waiting for " + description)
	return completed


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
